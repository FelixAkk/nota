(function() {
  var Backbone, Path, TemplateHelper, chalk, cheerio, fs, s, _;

  fs = require('fs');

  _ = require('underscore')._;

  s = require('underscore.string');

  Backbone = require('backbone');

  Path = require('path');

  chalk = require('chalk');

  cheerio = require('cheerio');

  module.exports = TemplateHelper = (function() {
    function TemplateHelper(logWarning) {
      this.logWarning = logWarning;
      _.extend(this, Backbone.Events);
    }

    TemplateHelper.prototype.isFile = function(path) {
      return fs.existsSync(path) && fs.statSync(path).isFile();
    };

    TemplateHelper.prototype.isDirectory = function(path) {
      return fs.existsSync(path) && fs.statSync(path).isDirectory();
    };

    TemplateHelper.prototype.isData = function(path) {
      return this.isFile(path);
    };

    TemplateHelper.prototype.isTemplate = function(path) {
      return this.isDirectory(path);
    };

    TemplateHelper.prototype.getTemplatesIndex = function(basePath, logWarnings) {
      var definition, dir, index, templateDirs, warningMsg, _i, _len;
      if (logWarnings == null) {
        logWarnings = true;
      }
      if (!fs.existsSync(basePath)) {
        throw new Error("Templates basepath '" + basePath + "' doesn't exist");
      }
      templateDirs = fs.readdirSync(basePath);
      templateDirs = _.filter(templateDirs, (function(_this) {
        return function(dir) {
          return _this.isDirectory(Path.join(basePath, dir));
        };
      })(this));
      index = {};
      for (_i = 0, _len = templateDirs.length; _i < _len; _i++) {
        dir = templateDirs[_i];
        definition = this.getTemplateDefinition(Path.join(basePath, dir), logWarnings);
        if (definition.meta === 'not template') {
          warningMsg = "Template " + (chalk.cyan(dir)) + " has no mandatory " + (chalk.cyan('template.html')) + " file " + (chalk.gray('(omitting template)'));
          if (logWarnings) {
            if (typeof this.logWarning === "function") {
              this.logWarning(warningMsg);
            }
          }
          continue;
        }
        index[definition.dir] = definition;
      }
      return index;
    };

    TemplateHelper.prototype.getTemplateDefinition = function(dir, logWarnings) {
      var definitionPath, isDefined, template, warningMsg;
      if (logWarnings == null) {
        logWarnings = true;
      }
      if (!this.isDirectory(dir)) {
        throw new Error("Template '" + dir + "' not found");
      }
      isDefined = this.isFile(Path.join(dir, "bower.json"));
      if (!isDefined) {
        warningMsg = "Template " + (chalk.cyan(dir)) + " has no " + (chalk.cyan('bower.json')) + " definition " + (chalk.gray('(optional, but recommended)'));
        if (logWarnings) {
          if (typeof this.logWarning === "function") {
            this.logWarning(warningMsg);
          }
        }
        template = {
          meta: 'not found'
        };
      } else {
        definitionPath = Path.join(dir, "bower.json");
        template = JSON.parse(fs.readFileSync(definitionPath));
        template.meta = 'read';
        if (logWarnings) {
          this.checkDependencies(dir);
        }
      }
      if (template.name == null) {
        template.name = Path.basename(dir);
      }
      if (!fs.existsSync(Path.join(dir, "template.html"))) {
        template.meta = 'not template';
      }
      template.dir = Path.basename(dir);
      return template;
    };

    TemplateHelper.prototype.checkDependencies = function(templateDir) {
      var bower, bowerPath, checknwarn, node, nodePath;
      checknwarn = (function(_this) {
        return function(args) {
          var defType, deps, depsDir, devDeps, mngr;
          if (args[2] == null) {
            return;
          }
          defType = s.capitalize(args[0]);
          depsDir = Path.join(templateDir, args[0] + '_' + args[1]);
          deps = (args[2].dependencies != null) && _.keys(args[2].dependencies).length > 0;
          devDeps = (args[2].devDependencies != null) && _.keys(args[2].devDependencies).length > 0;
          if ((deps || devDeps) && !_this.isDirectory(depsDir)) {
            mngr = args[0] === 'node' ? 'npm' : args[0];
            return typeof _this.logWarning === "function" ? _this.logWarning("Template " + (chalk.cyan(templateDir)) + " has " + defType + " definition with dependencies, but no " + defType + " " + args[1] + " seem installed yet. Forgot " + (chalk.cyan(mngr + ' install')) + "?") : void 0;
          }
        };
      })(this);
      bowerPath = Path.join(templateDir, "bower.json");
      if (this.isFile(bowerPath)) {
        bower = JSON.parse(fs.readFileSync(bowerPath));
      }
      checknwarn(['bower', 'components', bower]);
      nodePath = Path.join(templateDir, "package.json");
      if (this.isFile(nodePath)) {
        node = JSON.parse(fs.readFileSync(nodePath));
      }
      return checknwarn(['node', 'modules', node]);
    };

    TemplateHelper.prototype.getExampleDataPath = function(templatePath) {
      var definition, exampleDataPath, _ref;
      definition = this.getTemplateDefinition(templatePath, false);
      if (((_ref = definition['nota']) != null ? _ref['exampleData'] : void 0) != null) {
        exampleDataPath = Path.join(templatePath, definition['nota']['exampleData']);
        if (this.isData(exampleDataPath)) {
          return exampleDataPath;
        } else if (logWarnings) {
          return typeof this.logWarning === "function" ? this.logWarning("Example data path declaration found in template definition, but file doesn't exist.") : void 0;
        }
      }
    };

    TemplateHelper.prototype.getTemplateType = function(templatePath) {
      var $, html, type;
      html = fs.readFileSync(Path.join(templatePath, 'template.html'), {
        encoding: 'utf8'
      });
      $ = cheerio.load(html);
      return type = $('script').length === 0 ? 'static' : 'scripted';
    };

    TemplateHelper.prototype.findTemplatePath = function(options) {
      var match, templatePath, templatesPath, _templatePath;
      templatePath = options.templatePath, templatesPath = options.templatesPath;
      if (templatePath == null) {
        throw new Error("Please provide a template with " + (chalk.cyan('--template=<directory>')));
      }
      if (!this.isTemplate(templatePath)) {
        if (this.isTemplate(_templatePath = "" + (process.cwd()) + "/" + templatePath)) {
          templatePath = _templatePath;
        } else if (this.isTemplate(_templatePath = "" + templatesPath + "/" + templatePath)) {
          templatePath = _templatePath;
        } else if ((match = _(this.getTemplatesIndex(templatesPath, false)).findWhere({
          name: templatePath
        })) != null) {
          throw new Error("No template at '" + templatePath + "'. But we did find a template which declares it's name as such. It's path is '" + match.dir + "'");
        } else {
          throw new Error("Failed to find template " + (chalk.cyan(templatePath)) + ". Try " + (chalk.cyan('--list')) + " for an overview of available templates.");
        }
      }
      return templatePath;
    };

    TemplateHelper.prototype.findDataPath = function(options) {
      var dataPath, required, templatePath, _dataPath, _ref;
      dataPath = options.dataPath, templatePath = options.templatePath;
      required = (_ref = options.document) != null ? _ref.modelDriven : void 0;
      if (dataPath != null) {
        if (this.isData(dataPath)) {
          dataPath;
        } else if (this.isData(_dataPath = "" + (process.cwd()) + "/" + dataPath)) {
          dataPath = _dataPath;
        } else if (this.isData(_dataPath = "" + templatePath + "/" + dataPath)) {
          dataPath = _dataPath;
        } else {
          throw new Error("Failed to find data '" + dataPath + "'.");
        }
      } else if (_dataPath = this.getExampleDataPath(templatePath)) {
        if (typeof this.logWarning === "function") {
          this.logWarning("No data provided. Using example data at " + (chalk.cyan(_dataPath)) + " as found in template definition.");
        }
        dataPath = _dataPath;
      } else {
        if (required === true) {
          throw new Error("Please provide data with " + (chalk.cyan('--data=<file path>')));
        } else if (required == null) {
          if (typeof this.logWarning === "function") {
            this.logWarning("No data has been provided or example data found. If your template is model driven and requires data, please provide data with " + (chalk.cyan('--data=<file path>')));
          }
        }
      }
      return dataPath;
    };

    TemplateHelper.prototype.findOutputPath = function(options) {
      var defaultFilename, meta, outputPath, preserve;
      outputPath = options.outputPath, meta = options.meta, defaultFilename = options.defaultFilename, preserve = options.preserve;
      if (outputPath != null) {
        if (this.isDirectory(outputPath)) {
          if ((meta != null ? meta.filename : void 0) != null) {
            outputPath = Path.join(outputPath, meta.filename);
          } else {
            outputPath = Path.join(outputPath, defaultFilename);
          }
        }
        if (this.isFile(outputPath) && !preserve) {
          if (typeof this.logWarning === "function") {
            this.logWarning("Overwriting with current render: " + outputPath);
          }
        }
      } else {
        if ((meta != null ? meta.filename : void 0) != null) {
          outputPath = meta.filename;
        } else {
          outputPath = defaultFilename;
        }
      }
      return outputPath;
    };

    return TemplateHelper;

  })();

}).call(this);