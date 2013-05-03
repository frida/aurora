define(["cs!./lib/i18n", "cs!./lib/events", "cs!./lib/services", "cs!./lib/presenters", "cs!./lib/views"], function(i18n, events, services, presenters, views) {
    return {
        I18n: i18n.I18n,
        Events: events.Events,
        services: services,
        presenters: presenters,
        views: views
    };
});
