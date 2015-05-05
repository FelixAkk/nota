_             = require('underscore')._
s             = require('underscore.string')
chalk         = require('chalk')
http          = require('http')
express       = require('express')
phantom       = require('phantom')
fs            = require('fs')
mkdirp        = require('mkdirp')
Q             = require('q')
Path          = require('path')
open          = require("open")
Backbone      = require('backbone')

Document      = require('./document')
TemplateUtils = require('./template_utils')
JobQueue      = require('./queue')

module.exports = class NotaServer

  constructor: ( @options, logging ) ->
    _.extend(@, Backbone.Events)

    { @log, @logEvent, @logError, @logWarning, @logClient, @logClientError } = logging

    { @serverAddress, @serverPort, @templatePath, @dataPath } = @options

    @helper = new TemplateUtils(@logWarning)
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
      res.send fs.readFileSync(@dataPath, encoding: 'utf8')

    @server.listen(@serverPort)
    @trigger "server:running"

    if @options.preview
      return @

    @document = new Document(@, @options.document)
    @document.on 'all', @logEvent

    if @options.listen
      @document.once 'page:ready', =>
        @listen().then deferred.resolve
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
  #   jobs = [
  #     {
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

    if arguments[0] instanceof JobQueue
      @jobQueue = arguments[0]
    else
      jobs    = arguments[0]
      options = arguments[1] or {}
      _.extend options, {
        deferFinish:  deferred
        templateType: @document.options.templateType
      }
      @jobQueue = new JobQueue(jobs, options)

    switch @jobQueue.options.templateType
      when 'static'   then @after 'page:rendered', => @renderStatic(@jobQueue)
      when 'scripted' then @after 'page:ready', =>  @renderScripted(@jobQueue)

    deferred.promise
          
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

  listen: ->
    deferred = Q.defer()
    bodyParser = require('body-parser')
    # For parsing request bodies to 'application/json'
    @app.use bodyParser.json()
    # For parsing application/x-www-form-urlencoded
    @app.use bodyParser.urlencoded extended: true
    
    @app.post '/render', @webRender
    @app.get  '/render', @webRenderInterface

    require('dns').lookup require('os').hostname(), (errLan, ipLan, fam)=>
      require('externalip') (errExt, ipExt)=>
        @log? """
          Listening at #{chalk.cyan 'http://localhost:'+@serverPort+'/render'} for POST requests

            LAN: http://#{ipLan}:#{@serverPort}
            WAN: http://#{ipExt}:#{@serverPort}

        """
        deferred.resolve()

    deferred.promise

  webRenderInterface: (req, res)=>
    res.send fs.readFileSync( "#{__dirname}/../assets/webrender.html" , encoding: 'utf8')

  webRender: (req, res)=>
    mkdirp @options.webrenderPath, (err)=>
      if err
        return @logError "Nota requires write access to #{chalk.cyan options.webrenderPath}. Error: #{err}"

      job = {
        data:           req.body
        outputPath:     @options.webrenderPath
      }

      @queue(job)
      .then (meta)->
        if meta[0].fail?
          res.send 'fuck' # profane Nota fuck yeah!
        else
          res.download Path.resolve meta[0].outputPath

  after: (event, callback, context)->
    if @document.state is event then callback.apply(context or @)
    else @document.once event, callback, context

  close: ->
    @trigger 'server:closing'
    @document.close()
    @server.close()
    @server.off 'all', @logEvent, @

