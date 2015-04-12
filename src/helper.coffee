fs            = require('fs')
_             = require('underscore')._
Backbone      = require('backbone')
Path          = require('path')
chalk         = require('chalk')

# Utility class to help it with common filesystem and template/data related questiosn
class NotaHelper

  constructor: ( @logWarning )->
    _.extend(@, Backbone.Events)

  isFile: ( path ) ->
    fs.existsSync(path) and fs.statSync(path).isFile()

  isDirectory: ( path ) ->
    fs.existsSync(path) and fs.statSync(path).isDirectory()

  isData: ( path ) ->
    @isFile(path)

  isTemplate: ( path ) ->
    @isDirectory(path)

  getTemplatesIndex: ( basePath, logWarnings = true ) ->
    if not fs.existsSync(basePath)
      throw new Error("Templates basepath '#{basePath}' doesn't exist")

    # Get an array of filenames (excluding '.' and '..')
    templateDirs = fs.readdirSync(basePath)
    # Filter out all the directories
    templateDirs = _.filter templateDirs, (dir)=>
      @isDirectory Path.join basePath, dir

    index = {}

    for dir in templateDirs
      definition = @getTemplateDefinition Path.join(basePath, dir)
      if definition.meta is 'not template'
        warningMsg = "Template #{chalk.magenta(dir)} has no mandatory
        template.html file #{chalk.gray '(omitting template)'}"
        @logWarning? warningMsg if logWarnings
        continue
      # Save the definition in the index with it's name as the key
      index[definition.dir] = definition
    # We're done here
    return index

  getTemplateDefinition: ( dir, logWarnings = true ) ->
    unless @isDirectory dir then throw new Error "Template '#{dir}' not found"
    # Get the template definition
    isDefined = @isFile( dir+"/bower.json")

    if not isDefined
      warningMsg = "Template #{chalk.magenta(dir)} has no 'bower.json' definition
      #{chalk.gray '(optional, but recommended)'}"
      @logWarning? warningMsg if logWarnings
      templateDefinition =
        # Default it's name to it's directory name in absence of an 'official
        # statement' so we at least have some unique identifier.
        name: Path.basename(dir)
        meta: 'not found'
    else
      definitionPath = dir+"/bower.json"
      templateDefinition = JSON.parse fs.readFileSync definitionPath
      templateDefinition.meta = 'read'
      # TODO: check template definition against scheme for reuiqre properties
      # (and throw warnings otherwise) and set .defintion = 'valid' if sufficient

    # Check requirements for tempalte
    if not fs.existsSync(dir+"/template.html")
      templateDefinition.meta = 'not template'

    # Supplement the definition with some meta data that is now available
    templateDefinition.dir = Path.basename(dir)
    return templateDefinition

  getInitData: ( options ) ->
    { templatePath, dataPath } = options
    # Little bundle of logic that we can call later if no data has been provided
    # to see if the template specified any example data.
    exampleData = =>
      try
        definition = @getTemplateDefinition templatePath
        if definition['nota']?['exampleData']?
          exampleDataPath = Path.join templatePath, definition['nota']['exampleData']
          if @isData exampleDataPath
            return JSON.parse fs.readFileSync exampleDataPath, encoding: 'utf8'
      catch e
        @logWarning? "Attempted to get example data of template but failed: #{e}"
        return null

    # Try to get the data if path is provided
    if dataPath?
      data = JSON.parse(fs.readFileSync(dataPath, encoding: 'utf8'))
    # Else we see if there is example data available
    else if (_data = exampleData())?
      @logWarning? "No data provided. Serving example data as found in template definition."
      data = _data
    # TODO: serving empty data is probably a bad idea API wise?
    else
      @logWarning? "No data provided or found. Serving empty object."
      data = {}

  findTemplatePath: ( options ) ->
    { templatePath, templatesPath } = options
    # Exit unless the --template and --data are passed
    unless templatePath?
      throw new Error("Please provide a template with --template=<directory>")
        
    # Find the correct template path
    unless @isTemplate(templatePath)

      if @isTemplate(_templatePath =
        "#{process.cwd()}/#{templatePath}")
        templatePath = _templatePath

      else if @isTemplate(_templatePath =
        "#{templatesPath}/#{templatePath}")
        templatePath = _templatePath

      else if (match = _(@getTemplatesIndex(templatesPath)).findWhere {name: templatePath})?
        throw new Error("No template at '#{templatePath}'. But we did find a
        template which declares it's name as such. It's path is '#{match.dir}'")

      else throw new Error("Failed to find template '#{templatePath}'.")
    templatePath

  findDataPath: ( options ) ->
    { dataPath, templatePath } = options
    return null unless dataPath?

    # Find the correct data path
    unless @isData(dataPath)

      if @isData(_dataPath = "#{process.cwd()}/#{dataPath}")
        dataPath = _dataPath

      else if @isData(_dataPath = "#{templatePath}/#{dataPath}")
        dataPath = _dataPath

      else throw new Error("Failed to find data '#{dataPath}'.")

    dataPath

module.exports = NotaHelper