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
    try {
      String jsonString = await rootBundle.loadString('lib/l10n/arb/app_${locale.languageCode}.arb');
      Map<String, dynamic> jsonMap = json.decode(jsonString);

      _localizedStrings = jsonMap.map((key, value) {
        if (key.startsWith('@')) {
          return MapEntry(key, value.toString());
        }
        return MapEntry(key, value.toString());
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  String translate(String key) {
    return _localizedStrings?[key] ?? key;
  }

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
  String get serverIp => translate('serverIp');
  String get serverPort => translate('serverPort');
  String get saveSettings => translate('saveSettings');
  String get testConnection => translate('testConnection');
  String get currentSettings => translate('currentSettings');
  String get quickSettings => translate('quickSettings');
  String get hints => translate('hints');
  String get androidEmulator => translate('androidEmulator');
  String get localhost => translate('localhost');
  String get localNetwork => translate('localNetwork');
  String get loading => translate('loading');
  String get error => translate('error');
  String get success => translate('success');
  String get cancel => translate('cancel');
  String get confirm => translate('confirm');
  String get search => translate('search');
  String get settings => translate('settings');
  String get profile => translate('profile');
  String get about => translate('about');
  String get version => translate('version');
  String get twoFactorAuth => translate('twoFactorAuth');
  String get twoFactorCode => translate('twoFactorCode');
  String get verify => translate('verify');
  String get enterTwoFactorCode => translate('enterTwoFactorCode');
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
