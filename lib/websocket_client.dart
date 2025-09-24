import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'models.dart';
import 'utils.dart';

class WebSocketClient {
  WebSocketChannel? _channel;
  late StreamController<Message> _messageController;
  late StreamController<WebRTCOffer> _webrtcController;
  bool _isConnected = false;

  WebSocketClient() {
    _messageController = StreamController<Message>.broadcast();
    _webrtcController = StreamController<WebRTCOffer>.broadcast();
  }

  Stream<Message> get messageStream => _messageController.stream;
  Stream<WebRTCOffer> get webrtcStream => _webrtcController.stream;
  bool get isConnected => _isConnected;

  Future<void> connect(String token) async {
    try {
      final config = await getServerConfig();
      final wsUrl = 'ws://${config['ip']}:${config['port']}';
      
      print('Connecting to WebSocket: $wsUrl');
      
      _channel = IOWebSocketChannel.connect(
        Uri.parse(wsUrl),
        headers: {'Authorization': 'Bearer $token'},
      );
      
      _channel!.stream.listen(
        (data) {
          print('WebSocket message received: $data');
          try {
            final messageData = json.decode(data);
            if (messageData['type'] == 'message') {
              _messageController.add(Message.fromJson(messageData));
            } else if (messageData['type'] == 'webrtc-offer') {
              _webrtcController.add(WebRTCOffer.fromJson(messageData));
            }
          } catch (e) {
            print('Error parsing WebSocket message: $e');
          }
        },
        onError: (error) {
          print('WebSocket error: $error');
          _isConnected = false;
        },
        onDone: () {
          print('WebSocket closed');
          _isConnected = false;
        },
      );
      
      _isConnected = true;
      print('WebSocket connected successfully');
    } catch (e) {
      print('WebSocket connection failed: $e');
      _isConnected = false;
    }
  }

  void sendMessage(String action, dynamic data) {
    if (_channel != null && _isConnected) {
      try {
        _channel!.sink.add(json.encode({'action': action, ...data}));
      } catch (e) {
        print('Error sending WebSocket message: $e');
      }
    }
  }

  void disconnect() {
    _isConnected = false;
    _channel?.sink.close();
    _messageController.close();
    _webrtcController.close();
  }
}
