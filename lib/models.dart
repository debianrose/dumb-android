class ApiResponse {
  final bool success;
  final dynamic data;
  final String? error;

  ApiResponse({required this.success, this.data, this.error});
}

class User {
  final String username;
  final String? avatar;

  User({required this.username, this.avatar});

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      username: json['username'],
      avatar: json['avatar'],
    );
  }
}

class Channel {
  final String id;
  final String name;
  final String createdBy;
  final int createdAt;
  final int memberCount;

  Channel({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.createdAt,
    required this.memberCount,
  });

  factory Channel.fromJson(Map<String, dynamic> json) {
    return Channel(
      id: json['id']?.toString() ?? 'unknown',
      name: json['name']?.toString() ?? 'Без названия',
      createdBy: json['createdBy']?.toString() ?? 'Неизвестно',
      createdAt: json['createdAt'] is int ? json['createdAt'] : 0,
      memberCount: json['memberCount'] is int ? json['memberCount'] : 0,
    );
  }
}

class Message {
  final String id;
  final String from;
  final String channel;
  final String text;
  final int ts;
  final String? replyTo;
  final FileAttachment? file;
  final VoiceAttachment? voice;

  Message({
    required this.id,
    required this.from,
    required this.channel,
    required this.text,
    required this.ts,
    this.replyTo,
    this.file,
    this.voice,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id']?.toString() ?? '',
      from: json['from']?.toString() ?? '',
      channel: json['channel']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      ts: json['ts'] is int ? json['ts'] : 0,
      replyTo: json['replyTo']?.toString(),
      file: json['file'] != null ? FileAttachment.fromJson(json['file']) : null,
      voice: json['voice'] != null ? VoiceAttachment.fromJson(json['voice']) : null,
    );
  }

  bool get isVoiceMessage => voice != null;
  bool get hasText => text.isNotEmpty;
  bool get hasFile => file != null;
}

class FileAttachment {
  final String filename;
  final String originalName;
  final String mimetype;
  final int size;
  final String downloadUrl;

  FileAttachment({
    required this.filename,
    required this.originalName,
    required this.mimetype,
    required this.size,
    required this.downloadUrl,
  });

  factory FileAttachment.fromJson(Map<String, dynamic> json) {
    return FileAttachment(
      filename: json['filename']?.toString() ?? '',
      originalName: json['originalName']?.toString() ?? '',
      mimetype: json['mimetype']?.toString() ?? '',
      size: json['size'] is int ? json['size'] : 0,
      downloadUrl: json['downloadUrl']?.toString() ?? '',
    );
  }
}

class VoiceAttachment {
  final String filename;
  final int duration;
  final String downloadUrl;

  VoiceAttachment({
    required this.filename,
    required this.duration,
    required this.downloadUrl,
  });

  factory VoiceAttachment.fromJson(Map<String, dynamic> json) {
    return VoiceAttachment(
      filename: json['filename']?.toString() ?? '',
      duration: json['duration'] is int ? json['duration'] : 0,
      downloadUrl: json['downloadUrl']?.toString() ?? '',
    );
  }
}

class TwoFASetup {
  final String secret;
  final String qrCodeUrl;

  TwoFASetup({required this.secret, required this.qrCodeUrl});

  factory TwoFASetup.fromJson(Map<String, dynamic> json) {
    return TwoFASetup(
      secret: json['secret']?.toString() ?? '',
      qrCodeUrl: json['qrCodeUrl']?.toString() ?? '',
    );
  }
}

class WebRTCOffer {
  final String from;
  final dynamic offer;
  final String channel;

  WebRTCOffer({required this.from, required this.offer, required this.channel});

  factory WebRTCOffer.fromJson(Map<String, dynamic> json) {
    return WebRTCOffer(
      from: json['from']?.toString() ?? '',
      offer: json['offer'],
      channel: json['channel']?.toString() ?? '',
    );
  }
}
