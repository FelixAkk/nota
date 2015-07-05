_               = require('underscore')._
s               = require('underscore.string')
chalk           = require('chalk')
http            = require('http')
express         = require('express')
phantom         = require('phantom')
fs              = require('fs')
Q               = require('q')
Path            = require('path')
open            = require("open")
Backbone        = require('backbone')

Document        = require('./document')
TemplateHelper  = require('./template_helper')
JobQueue        = require('./queue')

module.exports  = class NotaServer

  constructor: ( @options, logging ) ->
    _.extend(@, Backbone.Events)

    { @log, @logEvent, @logError, @logWarning, @logClient, @logClientError } = logging

    { @serverAddress, @serverPort, @templatePath, @dataPath } = @options

    @helper = new TemplateHelper(@logWarning)
    _.extend @options.document, templateType: @helper.getTemplateType(@templatePath)

    @on 'all', @logEvent, @


  start: ->
    deferred = Q.defer()
    @trigger "server:init"

    # Start express server to serve dependencies from a unified namespaces
    @app = express()
    @server = http.createServer(@app)

    # Open the server with servering the template path as root
    @app.use express.static(@templatePath)

    # Serve 'template.html' by default (instead of index.html default behaviour)
    # TODO: Why does this line not work instead:
    # @app.get '/', express.static("#{@templatePath}/template.html")
    @app.get '/',         (req, res)-> res.redirect("/template.html")
    # Expose some extras at the first specified subpaths
    @app.use '/lib/',     express.static("#{__dirname}/")
    @app.use '/assets/',  express.static("#{__dirname}/../assets/")
    @app.use '/vendor/',  express.static("#{__dirname}/../bower_components/")
    @app.use '/nota.js',  express.static("#{__dirname}/client.js")

    @app.get '/data', ( req, res ) =>
      res.setHeader 'Content-Type', 'application/json'
      res.send fs.readFileSync(@dataPath, encoding: 'utf8')

    @server.listen(@serverPort)
    @trigger "server:running"

    if @options.preview
      # Leave it at this ... just serving the web assets to the browser
      deferred.resolve()
    else 
      # Start up the virtual document
      @document = new Document(@, @options.document)
      @document.on 'all', @logEvent

      if @options.listen
        @document.once 'page:ready', =>
          @listen().then deferred.resolve()
      else
        @document.once 'page:ready', =>
          deferred.resolve()

    deferred.promise

  url: =>
    "http://#{@serverAddress}:#{@serverPort}/"

  webrenderUrl: =>
    "http://#{@serverAddress}:#{@serverPort}/render"

  serve: ( @dataPath )->

  # Call with either a JobQueue instance or
  # with (jobs , options) where
  #
  #   jobs = [{
  #       dataPath:   dataPath
  #       data:       obj (alternatively)
  #       outputPath: outputPath
  #       preserve:   true | false
  #     }]
  #
  #   options = {
  #     deferFinish:  deferred
  #     templateType: 'static' | 'scripted'
  #   }
  queue: ( ) ->
    deferred = Q.defer()

    @jobQueue = @parseQueueArgs(arguments, deferred)

    switch @jobQueue.options.templateType
      when 'static'   then @after 'page:rendered', => @renderStatic(@jobQueue)
      when 'scripted' then @after 'page:ready', =>  @renderScripted(@jobQueue)

    deferred.promise
          
  # Parses the arguments of the queue call. Which could be either a single
  # queue argument, and array of jobs with and options hash, or a single job
  # object with an options hash.
  parseQueueArgs: (args, deferred)->
    if args[0] instanceof JobQueue
      jobQueue = args[0]
    else

      if args[0] instanceof Array
        jobs  = args[0]
      else if args[0] instanceof Object and ( args[0].data? or args[0].dataPath? )
        jobs  = [ args[0] ] # Create new jobs array of the provided job object

      options = args[1] or {}

      _.extend options, {
        deferFinish:  deferred
        templateType: @document.options.templateType
      }

      jobQueue = new JobQueue(jobs, options)

  renderStatic: (queue)->
    # Dequeue the next job
    job = queue.nextJob()
    start = new Date()

    @document.capture(job).then (meta)=>
      finished = new Date()
      meta.duration = finished-start

      # Mark this one as completed.
      queue.jobCompleted(meta)

      # Recursively continue rendering what's left of the job queue untill
      # it's empty, then we're finished.
      unless queue.isFinished() then @renderStatic queue

  renderScripted: (queue)->
    if (inProgressJobs = queue.inProgress())
      @logWarning? """
      Attempting to render while already occupied with jobs:

      #{inProgressJobs}

      Rejecting this render call.

      For multithreaded rendering of a queue please create another server
      instance (don't forget to provide it with an unoccupied port).
      """
      return

    # Dequeue the next job
    job = queue.nextJob()
    start = new Date()

    @document.on 'error-timeout', (err)->
      meta = _.extend {}, job, { fail: err }
      postRender meta

    offerData = (job)=>
      deferred = Q.defer()

      data = job.data or JSON.parse fs.readFileSync(job.dataPath, encoding: 'utf8')
      @document.injectData(data).then -> deferred.resolve job

      deferred.promise

    renderJob = (job)=>
      deferred = Q.defer()

      @after 'page:rendered', => @document.capture job
      @document.once 'render:done', deferred.resolve

      deferred.promise

    postRender = (meta)=>
      finished = new Date()
      meta.duration = finished-start

      if meta.fail?
        queue.jobFailed     job, meta
      else
        queue.jobCompleted  job, meta

      @log? "Job duration: #{(meta.duration / 1000).toFixed(2)} seconds"

      # Recursively continue rendering what's left of the job queue untill
      # it's empty, then we're finished.
      unless queue.isFinished() then @renderScripted queue

    error = (err)->
      @logError err


    # Call the promise and wait for it to finish, then do some post-render
    # administration of render meta data and see if we're done or can continue
    # with the rest of the job queue.
    if job.dataPath? or job.data?
      offerData(job)
      .then renderJob
      .then postRender
      .catch error
    else
      renderJob(job)
      .then postRender
      .catch error

  # Start listening for HTTP render requests
  listen: ->
    deferred = Q.defer()

    # Load dependencies only needed for wendering service
    mkdirp     = require('mkdirp')
    bodyParser = require('body-parser')
    Handlebars = require('handlebars')
    multer     = require('multer')

    # PhantomJS page renderBase64 isn't available for PDF, so we can't render
    # to memory and buffer it there before sending it over to the client. So
    # we need somewhere on the filesystem to park it, a sort of webrender temp
    # dir, and then upload that file with the response. We need to be able to
    # create this dir (or it has to already exist) to continue.
    mkdirp @options.webrenderPath, (err)=> if err
      deferred.reject "Unable to create render output path 
      #{chalk.cyan options.webrenderPath}. Error: #{err}"

    # For parsing request bodies to 'application/json'
    @app.use bodyParser.json()
    # For parsing request bodies to 'application/x-www-form-urlencoded'
    @app.use bodyParser.urlencoded extended: true
    # For parsing request bodies to 'multipart/form-data'
    @app.use multer()
    
    @app.post '/render', @webRender
    @app.get  '/render', @webRenderInterface

    @log? "Listening at #{chalk.cyan 'http://localhost:'+@serverPort+'/render'} for POST requests"

    # For convenience try to do a local and external IP lookup (LAN and WAN)
    @ipLookups().then (@ip)=>
      if @ip.lan? then @log? "LAN: http://#{ip.lan}:#{@serverPort}/render"
      if @ip.wan? then @log? "WAN: http://#{ip.wan}:#{@serverPort}/render"

      deferred.resolve @ip

    .catch (err)=>
      # Don't log whatever error gets caught here as an error, because the LAN
      # and WAN IP lookups where are purely a convenience and optional.
      @log? err
      deferred.resolve {}

    # .finally ()=>
    #   global.webRenderHTML = template {
    #     template:     definition
    #     serverPort:   @serverPort
    #     ip:           @ip
    #   }

    deferred.promise

  ipLookups: ->
    deferred = Q.defer()

    timeout = 2000
    local   = @ipLookupLocal()
    ext     = @ipLookupExt()
    reject  = ->
      # If it's time to reject we see if any of both lookups has finished
      # and provide that (harvest what you can so to say).
      if local.inspect().status is "fulfilled"
        return deferred.resolve lan: local.inspect().value
      if ext.inspect().status   is "fulfilled"
        return deferred.resolve wan: ext.inspect().value
      # If we got here we got nothing ...
      deferred.reject "LAN and WAN IP lookup canceled after timeout of #{timeout}ms"

    # We give the lookup 2 seconds to keep the CLI command responsive
    setTimeout reject, timeout

    # If we're not yet rejected and both resolved, we provide both IP addresses
    local.then (localIp)-> ext.then (extIp)->
      deferred.resolve {
        lan: localIp
        wan: extIp
      }

    deferred.promise

  ipLookupLocal: ->
    deferred = Q.defer()

    require('dns').lookup require('os').hostname(), (errLan, ipLan, fam)=>
      if errLan? then return deferred.reject errLan
      deferred.resolve ipLan

    deferred.promise

  ipLookupExt: ->
    deferred = Q.defer()

    require('externalip') (errExt, ipExt)=>
      if errExt? then return deferred.reject errExt
      deferred.resolve ipExt

    deferred.promise

  webRenderInterface: (req, res)=>
    html = fs.readFileSync( "#{__dirname}/../assets/webrender.html" , encoding: 'utf8')
    template = Handlebars.compile html
    definition = @helper.getTemplateDefinition(@templatePath)
    webRenderHTML = template({
      template:     definition
      serverPort:   @serverPort
      ip:           @ip
    })
    res.send webRenderHTML

  webRender: (req, res)=>
    console.log req.body

    return 
    job = {
      data:           req.body
      outputPath:     @options.webrenderPath
    }

    @queue(job).then (meta)->
      if meta[0].fail?
        res.send 'fuck' # profane Nota fuck yeah!
      else
        pdf = Path.resolve meta[0].outputPath
        res.download pdf

  after: (event, callback, context)->
    if @document.state is event then callback.apply(context or @)
    else @document.once event, callback, context

  close: ->
    @trigger 'server:closing'
    @document.close()
    @server.close()
    @server.off 'all', @logEvent, @

