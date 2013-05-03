/**
 * @license cs 0.4.1 Copyright (c) 2010-2011, The Dojo Foundation All Rights Reserved.
 * Available via the MIT or new BSD license.
 * see: http://github.com/jrburke/require-cs for details
 */

/*jslint */
/*global define, window, XMLHttpRequest, importScripts, Packages, java,
  ActiveXObject, process, require */

define([], function () {
    'use strict';
    var less, fs, getXhr,
        progIds = ['Msxml2.XMLHTTP', 'Microsoft.XMLHTTP', 'Msxml2.XMLHTTP.4.0'],
        fetchText = function () {
            throw new Error('Environment unsupported.');
        },
        buildMap = {};

    if (typeof process !== "undefined" &&
               process.versions &&
               !!process.versions.node) {
        //Using special require.nodeRequire, something added by r.js.
        less = require.nodeRequire('less');
        fs = require.nodeRequire('fs');
        fetchText = function (path, callback) {
            callback(fs.readFileSync(path, 'utf8'));
        };
    } else if ((typeof window !== "undefined" && window.navigator && window.document) || typeof importScripts !== "undefined") {
        // Browser action
        less = require("less");
        getXhr = function () {
            //Would love to dump the ActiveX crap in here. Need IE 6 to die first.
            var xhr, i, progId;
            if (typeof XMLHttpRequest !== "undefined") {
                return new XMLHttpRequest();
            } else {
                for (i = 0; i < 3; i++) {
                    progId = progIds[i];
                    try {
                        xhr = new ActiveXObject(progId);
                    } catch (e) {}

                    if (xhr) {
                        progIds = [progId];  // so faster next time
                        break;
                    }
                }
            }

            if (!xhr) {
                throw new Error("getXhr(): XMLHttpRequest not available");
            }

            return xhr;
        };

        fetchText = function (url, callback) {
            var xhr = getXhr();
            xhr.open('GET', url, true);
            xhr.onreadystatechange = function (evt) {
                if (xhr.readyState === 4) {
                    var response = xhr.responseText;
                    if (xhr.status !== 200)
                        response = null;
                    callback(response);
                }
            };
            xhr.send(null);
        };
        // end browser.js adapters
    } else if (typeof Packages !== 'undefined') {
        //Why Java, why is this so awkward?
        less = require("less");
        fetchText = function (path, callback) {
            var encoding = "utf-8",
                file = new java.io.File(path),
                lineSeparator = java.lang.System.getProperty("line.separator"),
                input = new java.io.BufferedReader(new java.io.InputStreamReader(new java.io.FileInputStream(file), encoding)),
                stringBuffer, line,
                content = '';
            try {
                stringBuffer = new java.lang.StringBuffer();
                line = input.readLine();

                // Byte Order Mark (BOM) - The Unicode Standard, version 3.0, page 324
                // http://www.unicode.org/faq/utf_bom.html

                // Note that when we use utf-8, the BOM should appear as "EF BB BF", but it doesn't due to this bug in the JDK:
                // http://bugs.sun.com/bugdatabase/view_bug.do?bug_id=4508058
                if (line && line.length() && line.charAt(0) === 0xfeff) {
                    // Eat the BOM, since we've already found the encoding on this file,
                    // and we plan to concatenating this buffer with others; the BOM should
                    // only appear at the top of a file.
                    line = line.substring(1);
                }

                stringBuffer.append(line);

                while ((line = input.readLine()) !== null) {
                    stringBuffer.append(lineSeparator);
                    stringBuffer.append(line);
                }
                //Make sure we return a JavaScript string and not a Java string.
                content = String(stringBuffer.toString()); //String
            } finally {
                input.close();
            }
            callback(content);
        };
    }

    function jsEscape (content) {
        return content.replace(/(['\\])/g, '\\$1')
            .replace(/[\f]/g, "\\f")
            .replace(/[\b]/g, "\\b")
            .replace(/[\n]/g, "\\n")
            .replace(/[\t]/g, "\\t")
            .replace(/[\r]/g, "\\r");
    }

    return {
        get: function () {
            return less;
        },

        write: function (pluginName, name, write) {
            if (buildMap.hasOwnProperty(name)) {
                write.asModule(pluginName + "!" + name, "define(function () { return undefined; });");
            }
        },

        writeFile: function (pluginName, name, parentRequire, write, config) {
            if (buildMap.hasOwnProperty(name)) {
                var css = buildMap[name];

                /* FIXME: tweaking CSS image paths should be done by grunt.js */
                css = css.replace(/(url\(")(\/img\/.+?"\))/g, function($0, $1, $2) { return $1 + ".." + $2; });

                write(parentRequire.toUrl(name + ".css"), css);
            }
        },

        version: '0.1.0',

        load: function (name, parentRequire, load, config) {
            var sourceUrl, pos, sourceDir;
            sourceUrl = parentRequire.toUrl(name + ".less");
            if (!config.isBuild)
                sourceUrl = "http://127.0.0.1:8010/" + sourceUrl;
            pos = sourceUrl.lastIndexOf('/');
            if (pos === -1)
                sourceDir = "/";
            else
                sourceDir = sourceUrl.substr(0, pos + 1);
            fetchText(sourceUrl, function (source) {
                if (!source) {
                    load.error("Error: Failed to fetch '" + sourceUrl + "'. Is 'grunt server' running?");
                    return;
                }

                var optimization, compress;
                if (config.isBuild) {
                    optimization = 3;
                    compress = true;
                } else {
                    optimization = 0;
                    compress = false;
                }

                var parser = new less.Parser({
                    optimization: optimization,
                    paths: [ sourceDir ]
                });
                parser.parse(source, function (err, tree) {
                    if (err) {
                        load.error(err);
                        return;
                    }

                    var css = tree.toCSS({
                        compress: compress,
                        yuicompress: compress
                    });

                    if (config.isBuild) {
                        buildMap[name] = css;
                    } else if (typeof window !== 'undefined') {
                        var nextElement = null;
                        var elements = document.head.getElementsByTagName("style");
                        if (elements.length > 0)
                            nextElement = elements[0];
                        var style = document.createElement("style");
                        style.type = "text/css";
                        if (style.styleSheet)
                            style.styleSheet.cssText = css;
                        else
                            style.appendChild(document.createTextNode(css));
                        if (nextElement === null)
                            document.head.appendChild(style);
                        else
                            document.head.insertBefore(style, nextElement);
                    }

                    load(css);
                });
            });
        }
    };
});
