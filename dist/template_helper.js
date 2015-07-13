(function() {
  var Backbone, Path, TemplateHelper, _, chalk, cheerio, fs, s;

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
      var definition, dir, i, index, len, templateDirs, warningMsg;
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
      for (i = 0, len = templateDirs.length; i < len; i++) {
        dir = templateDirs[i];
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
        index[definition.path] = definition;
      }
      return index;
    };

    TemplateHelper.prototype.getTemplateDefinition = function(dir, logWarnings) {
      var bower, bowerPath, definition, definitionPath, isDefined, npm, npmPath, warningMsg;
      if (logWarnings == null) {
        logWarnings = true;
      }
      if (!this.isDirectory(dir)) {
        throw new Error("Template '" + dir + "' not found");
      }
      isDefined = this.isFile(Path.join(dir, "nota.json"));
      if (!isDefined) {
        warningMsg = "Template " + (chalk.cyan(dir)) + " has no " + (chalk.cyan('nota.json')) + " definition " + (chalk.gray('(optional, but recommended)'));
        if (logWarnings) {
          if (typeof this.logWarning === "function") {
            this.logWarning(warningMsg);
          }
        }
        if (this.isFile(Path.join(dir, "bower.json"))) {
          bowerPath = Path.join(dir, "bower.json");
          bower = JSON.parse(fs.readFileSync(bowerPath));
          definition = _.pick(bower, ['name']);
          definition.meta = 'fallback';
        } else if (this.isFile(Path.join(dir, "package.json"))) {
          npmPath = Path.join(dir, "package.json");
          npm = JSON.parse(fs.readFileSync(npmPath));
          definition = _.pick(npm, ['name']);
          definition.meta = 'fallback';
        } else {
          definition = {
            meta: 'not found'
          };
        }
      } else {
        definitionPath = Path.join(dir, "nota.json");
        definition = JSON.parse(fs.readFileSync(definitionPath));
        definition.meta = 'read';
        if (logWarnings) {
          this.checkDependencies(dir);
        }
      }
      if (definition.name == null) {
        definition.name = Path.basename(dir);
      }
      if (!fs.existsSync(Path.join(dir, "template.html"))) {
        definition.meta = 'not template';
      }
      definition.path = dir;
      return definition;
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
      var definition, exampleDataPath;
      definition = this.getTemplateDefinition(templatePath, false);
      if ((definition != null ? definition['exampleData'] : void 0) != null) {
        exampleDataPath = Path.join(templatePath, definition['exampleData']);
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
      var _templatePath, match, template, templatePath, templatesPath;
      templatesPath = options.templatesPath, template = options.template;
      templatePath = template.path;
      if (templatePath == null) {
        throw new Error("Please provide a template with " + (chalk.cyan('--template=<directory>')));
      }
      if (!this.isTemplate(templatePath)) {
        if (this.isTemplate(_templatePath = (process.cwd()) + "/" + templatePath)) {
          templatePath = _templatePath;
        } else if (this.isTemplate(_templatePath = templatesPath + "/" + templatePath)) {
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
      var _dataPath, dataPath, template;
      dataPath = options.dataPath, template = options.template;
      if (dataPath != null) {
        if (this.isData(dataPath)) {
          dataPath;
        } else if (this.isData(_dataPath = (process.cwd()) + "/" + dataPath)) {
          dataPath = _dataPath;
        } else if (this.isData(_dataPath = template.path + "/" + dataPath)) {
          dataPath = _dataPath;
        } else {
          throw new Error("Failed to find data '" + dataPath + "'.");
        }
      } else if (_dataPath = this.getExampleDataPath(template.path)) {
        if (typeof this.logWarning === "function") {
          this.logWarning("No data provided. Using example data at " + (chalk.cyan(_dataPath)) + " as found in template definition.");
        }
        dataPath = _dataPath;
      } else {
        if (typeof this.logWarning === "function") {
          this.logWarning("No data has been provided or example data found. If your template is model driven and requires data, please provide data with " + (chalk.cyan('--data=<file path>')));
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
