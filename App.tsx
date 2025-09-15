import React, { useEffect, useRef, useState } from 'react';
import { View, Text, TextInput, Button, FlatList, StyleSheet, TouchableOpacity, Alert, ActivityIndicator, Image } from 'react-native';

const API_URL = 'http://0.0.0.0:3000';
const WS_URL = 'ws://0.0.0.0:3000/ws';

interface Message {
  id: string;
  from: string;
  text: string;
  ts: number;
  replyTo?: string;
  file?: {
    filename: string;
    originalName: string;
    mimetype: string;
    size: number;
    downloadUrl: string;
  };
  voice?: {
    filename: string;
    duration: number;
    downloadUrl: string;
  };
}

interface Channel {
  name: string;
  createdBy: string;
  createdAt: number;
  memberCount: number;
}

interface User {
  username: string;
  avatar?: string;
}

export default function App() {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [token, setToken] = useState('');
  const [connected, setConnected] = useState(false);
  const [loading, setLoading] = useState(false);
  const [currentView, setCurrentView] = useState<'login' | 'register' | 'main'>('login');
  const [channel, setChannel] = useState('general');
  const [channels, setChannels] = useState<Channel[]>([]);
  const [message, setMessage] = useState('');
  const [messages, setMessages] = useState<Message[]>([]);
  const [channelMembers, setChannelMembers] = useState<User[]>([]);
  const [newChannelName, setNewChannelName] = useState('');
  const [twoFactorToken, setTwoFactorToken] = useState('');
  const [requires2FA, setRequires2FA] = useState(false);
  const [sessionId, setSessionId] = useState('');

  const ws = useRef<WebSocket | null>(null);

  const apiRequest = async (endpoint: string, method: string = 'POST', body?: any) => {
    try {
      const headers: HeadersInit = {
        'Content-Type': 'application/json',
      };

      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }

      const response = await fetch(`${API_URL}${endpoint}`, {
        method,
        headers,
        body: body ? JSON.stringify(body) : undefined,
      });

      return await response.json();
    } catch (error) {
      console.error('API request error:', error);
      Alert.alert('Error', 'Network error');
      return { success: false, error: 'network error' };
    }
  };

  const handleLogin = async () => {
    setLoading(true);
    const result = await apiRequest('/api/login', 'POST', {
      username,
      password,
      twoFactorToken: requires2FA ? twoFactorToken : undefined
    });

    if (result.success) {
      setToken(result.token);
      setConnected(true);
      setCurrentView('main');
      Alert.alert('Success', 'Logged in successfully');
    } else if (result.requires2FA) {
      setRequires2FA(true);
      setSessionId(result.sessionId);
      Alert.alert('2FA Required', 'Please enter your 2FA code');
    } else {
      Alert.alert('Error', result.error || 'Login failed');
    }
    setLoading(false);
  };

  const handleRegister = async () => {
    setLoading(true);
    const result = await apiRequest('/api/register', 'POST', {
      username,
      password
    });

    if (result.success) {
      Alert.alert('Success', 'Registration successful. Please login.');
      setCurrentView('login');
    } else {
      Alert.alert('Error', result.error || 'Registration failed');
    }
    setLoading(false);
  };

  const loadChannels = async () => {
    const result = await apiRequest('/api/channels', 'GET');
    if (result.success) {
      setChannels(result.channels);
    }
  };

  const loadMessages = async () => {
    const result = await apiRequest(`/api/messages?channel=${channel}&limit=100`, 'GET');
    if (result.success) {
      setMessages(result.messages);
    }
  };

  const loadChannelMembers = async () => {
    const result = await apiRequest(`/api/channels/members?channel=${channel}`, 'GET');
    if (result.success) {
      setChannelMembers(result.members);
    }
  };

  const joinChannel = async (channelName: string) => {
    const result = await apiRequest('/api/channels/join', 'POST', {
      channel: channelName
    });
    
    if (result.success) {
      setChannel(channelName);
      Alert.alert('Success', `Joined channel ${channelName}`);
      loadChannels();
      loadMessages();
      loadChannelMembers();
    } else {
      Alert.alert('Error', result.error || 'Failed to join channel');
    }
  };

  const createChannel = async () => {
    if (!newChannelName.trim()) {
      Alert.alert('Error', 'Channel name cannot be empty');
      return;
    }

    const result = await apiRequest('/api/channels/create', 'POST', {
      channelName: newChannelName
    });

    if (result.success) {
      setNewChannelName('');
      Alert.alert('Success', `Channel ${result.channel} created`);
      loadChannels();
      joinChannel(result.channel);
    } else {
      Alert.alert('Error', result.error || 'Failed to create channel');
    }
  };

  const sendMessage = async () => {
    if (!message.trim()) return;

    const result = await apiRequest('/api/message', 'POST', {
      channel,
      text: message
    });

    if (result.success) {
      setMessage('');
      setMessages(prev => [result.message, ...prev]);
    } else {
      Alert.alert('Error', result.error || 'Failed to send message');
    }
  };

  const setupWebSocket = () => {
    if (ws.current) {
      ws.current.close();
    }

    ws.current = new WebSocket(`${WS_URL}?token=${token}`);
    
    ws.current.onopen = () => {
      setConnected(true);
      console.log('WebSocket connected');
    };

    ws.current.onmessage = (e) => {
      try {
        const data = JSON.parse(e.data);
        
        if (data.type === 'message' && data.msg.channel === channel) {
          setMessages(prev => [data.msg, ...prev]);
        }
        
        // Handle WebRTC signals, calls, etc.
        console.log('WebSocket message:', data);
      } catch (error) {
        console.error('WebSocket message parse error:', error);
      }
    };

    ws.current.onerror = (e) => {
      console.log('WebSocket error:', e);
      Alert.alert('WebSocket Error', 'Connection error');
    };

    ws.current.onclose = () => {
      setConnected(false);
      console.log('WebSocket disconnected');
    };
  };

  useEffect(() => {
    if (token && currentView === 'main') {
      setupWebSocket();
      loadChannels();
      loadMessages();
      loadChannelMembers();
    }
  }, [token, channel, currentView]);

  const renderMessage = ({ item }: { item: Message }) => (
    <View style={styles.messageContainer}>
      <Text style={styles.messageUser}>{item.from}:</Text>
      <Text style={styles.messageText}>{item.text}</Text>
      {item.file && (
        <TouchableOpacity onPress={() => console.log('Download file:', item.file)}>
          <Text style={styles.fileLink}>📎 {item.file.originalName}</Text>
        </TouchableOpacity>
      )}
      {item.voice && (
        <TouchableOpacity onPress={() => console.log('Play voice:', item.voice)}>
          <Text style={styles.voiceLink}>🎤 Voice message</Text>
        </TouchableOpacity>
      )}
      <Text style={styles.messageTime}>
        {new Date(item.ts).toLocaleTimeString()}
      </Text>
    </View>
  );

  const renderChannel = ({ item }: { item: Channel }) => (
    <TouchableOpacity
      style={[styles.channelItem, channel === item.name && styles.activeChannel]}
      onPress={() => joinChannel(item.name)}
    >
      <Text style={styles.channelName}>#{item.name}</Text>
      <Text style={styles.channelInfo}>
        {item.memberCount} members • {new Date(item.createdAt).toLocaleDateString()}
      </Text>
    </TouchableOpacity>
  );

  if (currentView === 'login' || currentView === 'register') {
    return (
      <View style={styles.container}>
        <Text style={styles.title}>
          {currentView === 'login' ? 'Login' : 'Register'}
        </Text>
        
        <TextInput
          style={styles.input}
          placeholder="Username"
          value={username}
          onChangeText={setUsername}
          autoCapitalize="none"
        />
        
        <TextInput
          style={styles.input}
          placeholder="Password"
          value={password}
          onChangeText={setPassword}
          secureTextEntry
        />

        {requires2FA && (
          <TextInput
            style={styles.input}
            placeholder="2FA Code"
            value={twoFactorToken}
            onChangeText={setTwoFactorToken}
            keyboardType="numeric"
          />
        )}

        {loading ? (
          <ActivityIndicator size="large" style={styles.loader} />
        ) : (
          <>
            <Button
              title={currentView === 'login' ? 'Login' : 'Register'}
              onPress={currentView === 'login' ? handleLogin : handleRegister}
            />
            
            <TouchableOpacity
              style={styles.switchButton}
              onPress={() => setCurrentView(currentView === 'login' ? 'register' : 'login')}
            >
              <Text style={styles.switchText}>
                {currentView === 'login' ? 'Need an account? Register' : 'Have an account? Login'}
              </Text>
            </TouchableOpacity>
          </>
        )}
      </View>
    );
  }

  return (
    <View style={styles.container}>
      {/* Header */}
      <View style={styles.header}>
        <Text style={styles.headerTitle}>#{channel}</Text>
        <Text style={styles.connectionStatus}>
          {connected ? '🟢 Connected' : '🔴 Disconnected'}
        </Text>
      </View>

      {/* Main Content */}
      <View style={styles.mainContent}>
        {/* Channels Sidebar */}
        <View style={styles.sidebar}>
          <Text style={styles.sidebarTitle}>Channels</Text>
          
          <FlatList
            data={channels}
            renderItem={renderChannel}
            keyExtractor={item => item.name}
            style={styles.channelList}
          />
          
          <View style={styles.createChannel}>
            <TextInput
              style={styles.smallInput}
              placeholder="New channel"
              value={newChannelName}
              onChangeText={setNewChannelName}
            />
            <Button title="Create" onPress={createChannel} />
          </View>
        </View>

        {/* Messages Area */}
        <View style={styles.messagesArea}>
          <FlatList
            data={messages}
            renderItem={renderMessage}
            keyExtractor={item => item.id}
            inverted
            style={styles.messagesList}
          />
          
          <View style={styles.inputArea}>
            <TextInput
              style={styles.messageInput}
              placeholder="Type a message..."
              value={message}
              onChangeText={setMessage}
              multiline
            />
            <Button title="Send" onPress={sendMessage} />
          </View>
        </View>

        {/* Members Sidebar */}
        <View style={styles.sidebar}>
          <Text style={styles.sidebarTitle}>Members</Text>
          <FlatList
            data={channelMembers}
            renderItem={({ item }) => (
              <View style={styles.memberItem}>
                {item.avatar ? (
                  <Image
                    source={{ uri: `${API_URL}/api/user/${item.username}/avatar` }}
                    style={styles.avatar}
                  />
                ) : (
                  <View style={styles.avatarPlaceholder}>
                    <Text style={styles.avatarText}>
                      {item.username.charAt(0).toUpperCase()}
                    </Text>
                  </View>
                )}
                <Text style={styles.memberName}>{item.username}</Text>
              </View>
            )}
            keyExtractor={item => item.username}
          />
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    marginBottom: 20,
    textAlign: 'center',
  },
  input: {
    borderWidth: 1,
    borderColor: '#ccc',
    padding: 12,
    marginBottom: 15,
    borderRadius: 5,
  },
  smallInput: {
    borderWidth: 1,
    borderColor: '#ccc',
    padding: 8,
    marginBottom: 10,
    borderRadius: 5,
    flex: 1,
  },
  loader: {
    margin: 20,
  },
  switchButton: {
    marginTop: 20,
    padding: 10,
  },
  switchText: {
    color: '#007AFF',
    textAlign: 'center',
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: 15,
    borderBottomWidth: 1,
    borderBottomColor: '#ccc',
  },
  headerTitle: {
    fontSize: 18,
    fontWeight: 'bold',
  },
  connectionStatus: {
    fontSize: 12,
    color: '#666',
  },
  mainContent: {
    flex: 1,
    flexDirection: 'row',
  },
  sidebar: {
    width: 200,
    borderRightWidth: 1,
    borderRightColor: '#ccc',
    padding: 10,
  },
  sidebarTitle: {
    fontWeight: 'bold',
    marginBottom: 10,
  },
  channelList: {
    flex: 1,
  },
  channelItem: {
    padding: 10,
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  activeChannel: {
    backgroundColor: '#e3f2fd',
  },
  channelName: {
    fontWeight: 'bold',
  },
  channelInfo: {
    fontSize: 12,
    color: '#666',
  },
  createChannel: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 10,
  },
  messagesArea: {
    flex: 1,
    justifyContent: 'space-between',
  },
  messagesList: {
    flex: 1,
    padding: 10,
  },
  messageContainer: {
    padding: 10,
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
    marginBottom: 5,
  },
  messageUser: {
    fontWeight: 'bold',
    color: '#007AFF',
  },
  messageText: {
    marginVertical: 5,
  },
  messageTime: {
    fontSize: 12,
    color: '#666',
  },
  fileLink: {
    color: '#007AFF',
    marginTop: 5,
  },
  voiceLink: {
    color: '#FF3B30',
    marginTop: 5,
  },
  inputArea: {
    flexDirection: 'row',
    padding: 10,
    borderTopWidth: 1,
    borderTopColor: '#ccc',
    alignItems: 'center',
  },
  messageInput: {
    flex: 1,
    borderWidth: 1,
    borderColor: '#ccc',
    borderRadius: 20,
    padding: 10,
    marginRight: 10,
    maxHeight: 100,
  },
  memberItem: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 8,
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  avatar: {
    width: 32,
    height: 32,
    borderRadius: 16,
    marginRight: 10,
  },
  avatarPlaceholder: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: '#007AFF',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 10,
  },
  avatarText: {
    color: 'white',
    fontWeight: 'bold',
  },
  memberName: {
    fontSize: 14,
  },
});
