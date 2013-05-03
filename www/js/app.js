//>>excludeStart("productionExclude", pragmas.productionExclude);
requirejs.config({
    baseUrl: "js/lib",
    urlArgs: "bust=" + (new Date()).getTime(),
    paths: {
        'coffee-script':        "coffee-script/coffee-script",
        'cs':                   "require/cs",
        'less':                 "less/less",
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
        'lcss':                 { deps: ['less']                                    },
        'jquery':               {                   exports: 'jQuery'               },
        'jquery.dd':            { deps: ['jquery'], exports: 'jQuery.fn.msDropDown' }
    }
});
//>>excludeEnd("productionExclude");

require(["jquery", "beam/main", "cs!app/services", "cs!app/app"], function($, beam, services, app) {
  function initServices() {
    var registry = {};

    registry.bus = new beam.services.MessageBus(registry);
    registry.frida = new services.Frida(registry);

    return registry;
  };

  function startServices(services) {
    services.bus.start();
    services.frida.start();
  }

  $(function() {
    var services = initServices();
    var view = new app.View(null, $("[data-view='app']"));
    var presenter = new app.Presenter(null, view, services);
    startServices(services);
    window.app = {
      services: services,
      view: view,
      presenter: presenter
    }

    $(window).unload(function() {
      presenter.dispose();
      for (var name in services) {
        if (services.hasOwnProperty(name))
          services[name].dispose();
      }
      delete window.app;
    });
  });
});
