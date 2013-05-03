/*global module:false*/
module.exports = function(grunt) {
    grunt.initConfig({
        requirejs: {
            almond: true,
            replaceRequireScript: [{
                files: [ "build/index.html" ],
                module: "app"
            }],
            modules: [
                { name: "app", excludeShallow: [ 'coffee-script', 'cs' ] }
            ],
            stubModules: [ 'lcss' ],
            dir: "build",
            appDir: "www",
            baseUrl: "js/lib",
            paths: {
                'coffee-script':        "coffee-script/coffee-script",
                'cs':                   "require/cs",
                'lcss':                 "require/lcss",
                'jquery':               "jquery/jquery",
                'jquery.dd':            "jquery/jquery.dd",
                'three':                "three.js/ThreeWebGL",
                'three.extras':         "three.js/ThreeExtras",
                'three.raf':            "three.js/RequestAnimationFrame",
                'three.detector':       "three.js/Detector",
                'tween':                "tween.js/Tween",
                'globe':                "globe/globe",
                'beam':                 "beam/beam",
                'app':                  "../app",
                'css':                  "../../css"
            },
            shim: {
                'jquery':               {                   exports: 'jQuery'                    },
                'jquery.dd':            { deps: ['jquery'], exports: 'jQuery.fn.msDropDown'      },
                'app':                  { deps: ['almond']                                       }
            },
            fileExclusionRegExp: /^(.git|build|grunt\.js|node_modules|test|tools)$/,
            onBuildWrite: function(moduleName, path, contents) {
                /* strip off the "cs!" prefix */
                return contents.replace(/(['"])cs!([-.\/\w]+['"])/g, function($0, $1, $2) { return $1 + $2; });
            },
            optimizeAllPluginResources: true,
            optimize: 'uglify',
            uglify: {
                mangle: true
            },
            optimizeCss: 'none', /* LESS compiler takes care of this */
            useStrict: true,
            pragmas: {
                productionExclude: true
            }
        },
        trim: {
            dirs: "<%= requirejs.dir %>"
        }
    });

    grunt.loadNpmTasks('grunt-requirejs');

    grunt.registerTask('default', 'requirejs trim');

    grunt.registerMultiTask('trim', "Trim for packaging.", function() {
        var fs = require('fs');
        var path = require('path');

        grunt.file.expand(this.file.src).forEach(function(dir) {
            try {
                fs.unlinkSync(path.join(dir, "build.txt"));
            } catch (e) {
            }

            var ignoredSubDirs = [
                path.join(dir, "css", "lib"),
                path.join(dir, "js", "app"),
                path.join(dir, "js", "lib")
            ];
            ignoredSubDirs.forEach(function(subDir) {
                try {
                    rmTreeSync(subDir);
                } catch (e) {
                    console.log(e);
                }
            });

            var ignoredFiles = /\.(coffee|less)$/;
            grunt.file.recurse(dir, function(abspath, rootdir, subdir, filename) {
                if (ignoredFiles.test(filename))
                    fs.unlinkSync(abspath);
            });
        });

        function rmTreeSync(treePath) {
            if (!fs.existsSync(treePath))
                return;

            var files = fs.readdirSync(treePath);
            if (!files.length) {
                fs.rmdirSync(treePath);
                return;
            } else {
                files.forEach(function(file) {
                    var fullName = path.join(treePath, file);
                    if (fs.statSync(fullName).isDirectory()) {
                        rmTreeSync(fullName);
                    } else {
                        fs.unlinkSync(fullName);
                    }
                });
            }
            fs.rmdirSync(treePath);
        };
    });

    grunt.registerTask('server', "Start a devmode-friendly web server.", function() {
        var done = this.async();

        var connect = require('connect');
        var cors = require('connect-xcors');
        var path = require('path');

        var corsOptions = {
            origins: [],
            methods: ['HEAD', 'GET'],
            resources: [
                {
                    pattern: "/"
                }
            ]
        };
        connect()
            .use(connect.logger({ format: 'dev' }))
            .use(cors(corsOptions))
            .use(connect.static(path.join(__dirname, "www")))
            .listen(8010);

        grunt.log.writeln("Hit ENTER to finish.");
        process.stdin.resume();
        process.stdin.setEncoding('utf8');
        process.stdin.on('data', function(line) {
            process.stdin.pause();
            done();
        });
    });

};
