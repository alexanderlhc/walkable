import 'dart:ui';

/// Which measurement system distances and paces are displayed in. Walk data
/// itself is always stored in metres; this only affects formatting.
enum UnitSystem { metric, imperial }

const _imperialCountries = {'US', 'GB', 'LR', 'MM'};

/// The unit system implied by a device locale: imperial only for the few
/// countries that use miles, metric otherwise (including locales with no
/// country code).
UnitSystem unitSystemForLocale(Locale locale) =>
    _imperialCountries.contains(locale.countryCode?.toUpperCase())
        ? UnitSystem.imperial
        : UnitSystem.metric;
