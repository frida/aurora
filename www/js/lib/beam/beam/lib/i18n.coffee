define [], ->
  exports = {}


  class exports.I18n
    constructor: (@lang, @db) ->

    format: (catalog, key, context) ->
      if strings = @db.strings[catalog]
        if translations = strings[key]
          if translation = (translations[@lang] ? translations['en'])
            return @_eval(translation, context)
      return key

    _eval: (translation, context) ->
      translation?(context) ? translation


  return exports
