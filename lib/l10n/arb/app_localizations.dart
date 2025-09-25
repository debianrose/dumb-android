import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  Map<String, String>? _localizedStrings;

  Future<bool> load() async {
    String jsonString = await rootBundle.loadString('lib/l10n/arb/app_${locale.languageCode}.arb');
    Map<String, dynamic> jsonMap = json.decode(jsonString);

    _localizedStrings = jsonMap.map((key, value) {
      if (key.startsWith('@')) {
        return MapEntry(key, value.toString());
      }
      return MapEntry(key, value.toString());
    });

    return true;
  }

  String translate(String key) {
    return _localizedStrings?[key] ?? key;
  }

  // Геттеры для удобства (опционально)
  String get appTitle => translate('appTitle');
  String get login => translate('login');
  String get register => translate('register');
  String get username => translate('username');
  String get password => translate('password');
  String get channels => translate('channels');
  String get createChannel => translate('createChannel');
  String get joinChannel => translate('joinChannel');
  String get channelName => translate('channelName');
  String get sendMessage => translate('sendMessage');
  String get typeMessage => translate('typeMessage');
  String get noMessages => translate('noMessages');
  String get beFirstToMessage => translate('beFirstToMessage');
  String get members => translate('members');
  String get createdBy => translate('createdBy');
  String get leaveChannel => translate('leaveChannel');
  String get refresh => translate('refresh');
  String get serverSettings => translate('serverSettings');
  String get logout => translate('logout');
  String get noChannelsAvailable => translate('noChannelsAvailable');
  String get connectionError => translate('connectionError');
  String get retry => translate('retry');
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['en', 'ru', 'es', 'fr', 'de', 'zh', 'ja', 'ko', 'ar'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    AppLocalizations localizations = AppLocalizations(locale);
    await localizations.load();
    return localizations;
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
