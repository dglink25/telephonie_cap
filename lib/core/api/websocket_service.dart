import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';
import '../constants/app_constants.dart';

typedef EventCallback = void Function(dynamic data);

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  final PusherChannelsFlutter _pusher = PusherChannelsFlutter.getInstance();
  bool _initialized = false;

  final Map<String, PusherChannel> _channels = {};

  Future<void> init(String authToken) async {
    if (_initialized) return;

   await _pusher.init(
    apiKey: AppConstants.reverbAppKey,
    cluster: 'mt1',
    authEndpoint:
        '${AppConstants.baseUrl.replaceAll('/api', '')}/broadcasting/auth',
    onAuthorizer: (channelName, socketId, options) async {
      return {
        'headers': {'Authorization': 'Bearer $authToken'},
      };
    },
  );

    await _pusher.connect();
    _initialized = true;
  }

  Future<void> subscribeToPrivateChannel(
    String channelName, {
    required Map<String, EventCallback> events,
  }) async {
    final channel = await _pusher.subscribe(
      channelName: 'private-$channelName',
      onEvent: (event) {
        final handler = events[event.eventName];
        if (handler != null) handler(event.data);
      },
    );
    _channels['private-$channelName'] = channel;
  }

  Future<void> subscribeToPresenceChannel(
    String channelName, {
    required Map<String, EventCallback> events,
  }) async {
    final channel = await _pusher.subscribe(
      channelName: 'presence-$channelName',
      onEvent: (event) {
        final handler = events[event.eventName];
        if (handler != null) handler(event.data);
      },
    );
    _channels['presence-$channelName'] = channel;
  }

  Future<void> unsubscribe(String channelName) async {
    await _pusher.unsubscribe(channelName: channelName);
    _channels.remove(channelName);
  }

  Future<void> disconnect() async {
    await _pusher.disconnect();
    _initialized = false;
    _channels.clear();
  }

  bool get isConnected => _initialized;
}