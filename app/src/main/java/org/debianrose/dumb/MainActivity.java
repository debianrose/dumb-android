package org.debianrose.dumb;

import android.Manifest;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.media.MediaPlayer;
import android.media.MediaRecorder;
import android.net.Uri;
import android.os.AsyncTask;
import android.os.Bundle;
import android.os.Environment;
import android.os.Handler;
import android.text.TextUtils;
import android.util.Base64;
import android.util.Log;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import org.java_websocket.client.WebSocketClient;
import org.java_websocket.handshake.ServerHandshake;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URI;
import java.net.URL;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

public class MainActivity extends AppCompatActivity {

    private static final String TAG = "ChatClient";
    private static final String SERVER_URL = "http://0.0.0.0:3000";
    private static final String WS_URL = "ws://0.0.0.0:3000/ws";
    private static final int PERMISSION_REQUEST_CODE = 100;

    private static final String KEY_CURRENT_TOKEN = "current_token";
    private static final String KEY_CURRENT_USER = "current_user";
    private static final String KEY_CURRENT_CHANNEL = "current_channel";

    private EditText etUsername, etPassword, etMessage, etChannel;
    private Button btnLogin, btnRegister, btnSend, btnJoinChannel, btnCreateChannel;
    private ListView lvMessages, lvChannels;
    private LinearLayout loginLayout, chatLayout;
    private ImageView ivAvatar;
    private TextView tvUsername;

    private String currentToken = null;
    private String currentUser = null;
    private String currentChannel = null;
    private WebSocketClient webSocketClient;
    private List<Message> messages = new ArrayList<>();
    private List<String> channels = new ArrayList<>();
    private MessageAdapter messageAdapter;
    private ArrayAdapter<String> channelAdapter;

    private MediaRecorder mediaRecorder;
    private String audioFilePath;
    private boolean isRecording = false;
    private Button btnRecordVoice;
    private MediaPlayer mediaPlayer;

    private ScheduledExecutorService scheduler;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        if (savedInstanceState != null) {
            currentToken = savedInstanceState.getString(KEY_CURRENT_TOKEN);
            currentUser = savedInstanceState.getString(KEY_CURRENT_USER);
            currentChannel = savedInstanceState.getString(KEY_CURRENT_CHANNEL);
        }

        initViews();
        setupAdapters();
        checkPermissions();

        scheduler = Executors.newSingleThreadScheduledExecutor();

        if (currentToken != null && currentUser != null) {
            setupWebSocket();
            loadUserData();
            loginLayout.setVisibility(View.GONE);
            chatLayout.setVisibility(View.VISIBLE);
            loadChannels();
        }
    }

    @Override
    protected void onSaveInstanceState(@NonNull Bundle outState) {
        super.onSaveInstanceState(outState);
        outState.putString(KEY_CURRENT_TOKEN, currentToken);
        outState.putString(KEY_CURRENT_USER, currentUser);
        outState.putString(KEY_CURRENT_CHANNEL, currentChannel);
    }

    private void initViews() {
        etUsername = findViewById(R.id.etUsername);
        etPassword = findViewById(R.id.etPassword);
        etMessage = findViewById(R.id.etMessage);
        etChannel = findViewById(R.id.etChannel);
        
        btnLogin = findViewById(R.id.btnLogin);
        btnRegister = findViewById(R.id.btnRegister);
        btnSend = findViewById(R.id.btnSend);
        btnJoinChannel = findViewById(R.id.btnJoinChannel);
        btnCreateChannel = findViewById(R.id.btnCreateChannel);
        btnRecordVoice = findViewById(R.id.btnRecordVoice);

        lvMessages = findViewById(R.id.lvMessages);
        lvChannels = findViewById(R.id.lvChannels);

        loginLayout = findViewById(R.id.loginLayout);
        chatLayout = findViewById(R.id.chatLayout);

        ivAvatar = findViewById(R.id.ivAvatar);
        tvUsername = findViewById(R.id.tvUsername);

        btnLogin.setOnClickListener(v -> login());
        btnRegister.setOnClickListener(v -> register());
        btnSend.setOnClickListener(v -> sendMessage());
        btnJoinChannel.setOnClickListener(v -> joinChannel());
        btnCreateChannel.setOnClickListener(v -> createChannel());
        btnRecordVoice.setOnClickListener(v -> toggleVoiceRecording());

        lvChannels.setOnItemClickListener((parent, view, position, id) -> {
            String channelJson = channels.get(position);
            switchChannel(channelJson);
        });
    }

    private void setupAdapters() {
        messageAdapter = new MessageAdapter();
        lvMessages.setAdapter(messageAdapter);

        channelAdapter = new ArrayAdapter<>(this, android.R.layout.simple_list_item_1, channels);
        lvChannels.setAdapter(channelAdapter);
    }

    private void checkPermissions() {
        String[] permissions = {
                Manifest.permission.INTERNET,
                Manifest.permission.RECORD_AUDIO,
                Manifest.permission.WRITE_EXTERNAL_STORAGE,
                Manifest.permission.READ_EXTERNAL_STORAGE
        };

        List<String> permissionsToRequest = new ArrayList<>();
        for (String permission : permissions) {
            if (ContextCompat.checkSelfPermission(this, permission) != PackageManager.PERMISSION_GRANTED) {
                permissionsToRequest.add(permission);
            }
        }

        if (!permissionsToRequest.isEmpty()) {
            ActivityCompat.requestPermissions(this, 
                    permissionsToRequest.toArray(new String[0]), PERMISSION_REQUEST_CODE);
        }
    }

    private void login() {
        String username = etUsername.getText().toString().trim();
        String password = etPassword.getText().toString().trim();

        if (TextUtils.isEmpty(username) || TextUtils.isEmpty(password)) {
            Toast.makeText(this, "Please enter username and password", Toast.LENGTH_SHORT).show();
            return;
        }

        new AsyncTask<Void, Void, JSONObject>() {
            @Override
            protected JSONObject doInBackground(Void... voids) {
                try {
                    JSONObject payload = new JSONObject();
                    payload.put("username", username);
                    payload.put("password", password);

                    return sendPostRequest("/api/login", payload);
                } catch (Exception e) {
                    Log.e(TAG, "Login error", e);
                    return null;
                }
            }

            @Override
            protected void onPostExecute(JSONObject result) {
                if (result != null && result.optBoolean("success")) {
                    currentToken = result.optString("token");
                    currentUser = username;
                    setupWebSocket();
                    loadUserData();
                    loginLayout.setVisibility(View.GONE);
                    chatLayout.setVisibility(View.VISIBLE);
                    loadChannels();
                    Toast.makeText(MainActivity.this, "Login successful", Toast.LENGTH_SHORT).show();
                } else {
                    String error = result != null ? result.optString("error", "Login failed") : "Login failed";
                    Toast.makeText(MainActivity.this, error, Toast.LENGTH_SHORT).show();
                }
            }
        }.execute();
    }

    private void register() {
        String username = etUsername.getText().toString().trim();
        String password = etPassword.getText().toString().trim();

        if (TextUtils.isEmpty(username) || TextUtils.isEmpty(password)) {
            Toast.makeText(this, "Please enter username and password", Toast.LENGTH_SHORT).show();
            return;
        }

        new AsyncTask<Void, Void, JSONObject>() {
            @Override
            protected JSONObject doInBackground(Void... voids) {
                try {
                    JSONObject payload = new JSONObject();
                    payload.put("username", username);
                    payload.put("password", password);

                    return sendPostRequest("/api/register", payload);
                } catch (Exception e) {
                    Log.e(TAG, "Register error", e);
                    return null;
                }
            }

            @Override
            protected void onPostExecute(JSONObject result) {
                if (result != null && result.optBoolean("success")) {
                    Toast.makeText(MainActivity.this, "Registration successful", Toast.LENGTH_SHORT).show();
                } else {
                    String error = result != null ? result.optString("error", "Registration failed") : "Registration failed";
                    Toast.makeText(MainActivity.this, error, Toast.LENGTH_SHORT).show();
                }
            }
        }.execute();
    }

    private void sendMessage() {
        String text = etMessage.getText().toString().trim();
        if (TextUtils.isEmpty(text) || currentChannel == null) {
            Toast.makeText(this, "Please select a channel and enter message", Toast.LENGTH_SHORT).show();
            return;
        }

        new AsyncTask<Void, Void, JSONObject>() {
            @Override
            protected JSONObject doInBackground(Void... voids) {
                try {
                    JSONObject payload = new JSONObject();
                    payload.put("channel", currentChannel);
                    payload.put("text", text);

                    return sendPostRequest("/api/message", payload);
                } catch (Exception e) {
                    Log.e(TAG, "Send message error", e);
                    return null;
                }
            }

            @Override
            protected void onPostExecute(JSONObject result) {
                if (result != null && result.optBoolean("success")) {
                    etMessage.setText("");
                    loadMessages();
                } else {
                    Toast.makeText(MainActivity.this, "Failed to send message", Toast.LENGTH_SHORT).show();
                }
            }
        }.execute();
    }

    private void joinChannel() {
        String channel = etChannel.getText().toString().trim();
        if (TextUtils.isEmpty(channel)) {
            Toast.makeText(this, "Please enter channel name", Toast.LENGTH_SHORT).show();
            return;
        }

        new AsyncTask<Void, Void, JSONObject>() {
            @Override
            protected JSONObject doInBackground(Void... voids) {
                try {
                    JSONObject payload = new JSONObject();
                    payload.put("channel", channel);

                    return sendPostRequest("/api/channels/join", payload);
                } catch (Exception e) {
                    Log.e(TAG, "Join channel error", e);
                    return null;
                }
            }

            @Override
            protected void onPostExecute(JSONObject result) {
                if (result != null && result.optBoolean("success")) {
                    loadChannels();
                    etChannel.setText("");
                    Toast.makeText(MainActivity.this, "Joined channel: " + channel, Toast.LENGTH_SHORT).show();
                } else {
                    Toast.makeText(MainActivity.this, "Failed to join channel", Toast.LENGTH_SHORT).show();
                }
            }
        }.execute();
    }

    private void createChannel() {
        String channel = etChannel.getText().toString().trim();
        if (TextUtils.isEmpty(channel)) {
            Toast.makeText(this, "Please enter channel name", Toast.LENGTH_SHORT).show();
            return;
        }

        new AsyncTask<Void, Void, JSONObject>() {
            @Override
            protected JSONObject doInBackground(Void... voids) {
                try {
                    JSONObject payload = new JSONObject();
                    payload.put("name", channel);

                    return sendPostRequest("/api/channels/create", payload);
                } catch (Exception e) {
                    Log.e(TAG, "Create channel error", e);
                    return null;
                }
            }

            @Override
            protected void onPostExecute(JSONObject result) {
                if (result != null && result.optBoolean("success")) {
                    loadChannels();
                    etChannel.setText("");
                    Toast.makeText(MainActivity.this, "Channel created: " + channel, Toast.LENGTH_SHORT).show();
                } else {
                    Toast.makeText(MainActivity.this, "Failed to create channel", Toast.LENGTH_SHORT).show();
                }
            }
        }.execute();
    }

    private void switchChannel(String channelJson) {
        try {
            JSONObject channelObj = new JSONObject(channelJson);
            String channelId = channelObj.getString("id");
            String channelName = channelObj.getString("name");
            
            new AsyncTask<Void, Void, JSONObject>() {
                @Override
                protected JSONObject doInBackground(Void... voids) {
                    try {
                        JSONObject payload = new JSONObject();
                        payload.put("channel", channelId);
                        return sendPostRequest("/api/channels/join", payload);
                    } catch (Exception e) {
                        Log.e(TAG, "Join channel error in switch", e);
                        return null;
                    }
                }
    
                @Override
                protected void onPostExecute(JSONObject result) {
                    if (result != null && result.optBoolean("success")) {
                        currentChannel = channelId;
                        Toast.makeText(MainActivity.this, "Switched to: " + channelName, Toast.LENGTH_SHORT).show();
                        loadMessages();
                    } else {
                        Toast.makeText(MainActivity.this, "Failed to join channel: " + channelName, Toast.LENGTH_SHORT).show();
                    }
                }
            }.execute();
        } catch (JSONException e) {
            Log.e(TAG, "Error parsing channel JSON", e);
            Toast.makeText(this, "Error switching channel", Toast.LENGTH_SHORT).show();
        }
    }

    private void loadMessages() {
        if (currentChannel == null) return;

        new AsyncTask<Void, Void, JSONObject>() {
            @Override
            protected JSONObject doInBackground(Void... voids) {
                try {
                    String url = SERVER_URL + "/api/messages?channel=" + Uri.encode(currentChannel) + "&limit=100";
                    return sendGetRequest(url);
                } catch (Exception e) {
                    Log.e(TAG, "Load messages error", e);
                    return null;
                }
            }

            @Override
            protected void onPostExecute(JSONObject result) {
                if (result != null && result.optBoolean("success")) {
                    messages.clear();
                    JSONArray messagesArray = result.optJSONArray("messages");
                    if (messagesArray != null) {
                        for (int i = 0; i < messagesArray.length(); i++) {
                            JSONObject msgObj = messagesArray.optJSONObject(i);
                            if (msgObj != null) {
                                Message message = new Message(
                                        msgObj.optString("id"),
                                        msgObj.optString("from"),
                                        msgObj.optString("text"),
                                        msgObj.optLong("ts"),
                                        msgObj.optString("channel")
                                );
                                messages.add(message);
                            }
                        }
                    }
                    messageAdapter.notifyDataSetChanged();
                    if (messages.size() > 0) {
                        lvMessages.smoothScrollToPosition(messages.size() - 1);
                    }
                } else {
                    Toast.makeText(MainActivity.this, "Failed to load messages", Toast.LENGTH_SHORT).show();
                }
            }
        }.execute();
    }

    private void loadChannels() {
        new AsyncTask<Void, Void, JSONObject>() {
            @Override
            protected JSONObject doInBackground(Void... voids) {
                try {
                    return sendGetRequest(SERVER_URL + "/api/channels");
                } catch (Exception e) {
                    Log.e(TAG, "Load channels error", e);
                    return null;
                }
            }
    
            @Override
            protected void onPostExecute(JSONObject result) {
                if (result != null && result.optBoolean("success")) {
                    channels.clear();
                    JSONArray channelsArray = result.optJSONArray("channels");
                    if (channelsArray != null) {
                        for (int i = 0; i < channelsArray.length(); i++) {
                            JSONObject channelObj = channelsArray.optJSONObject(i);
                            if (channelObj != null) {
                                channels.add(channelObj.toString());
                            }
                        }
                    }
                    channelAdapter.notifyDataSetChanged();
                    
                    if (currentChannel == null && !channels.isEmpty()) {
                        try {
                            switchChannel(channels.get(0));
                        } catch (Exception e) {
                            Log.e(TAG, "Error parsing first channel", e);
                        }
                    }
                } else {
                    Toast.makeText(MainActivity.this, "Failed to load channels", Toast.LENGTH_SHORT).show();
                }
            }
        }.execute();
    }
                    
    private void loadUserData() {
        new AsyncTask<Void, Void, Bitmap>() {
            @Override
            protected Bitmap doInBackground(Void... voids) {
                try {
                    String url = SERVER_URL + "/api/user/" + Uri.encode(currentUser) + "/avatar";
                    return downloadImage(url);
                } catch (Exception e) {
                    Log.e(TAG, "Load avatar error", e);
                    return null;
                }
            }

            @Override
            protected void onPostExecute(Bitmap bitmap) {
                if (bitmap != null) {
                    ivAvatar.setImageBitmap(bitmap);
                }
                tvUsername.setText(currentUser);
            }
        }.execute();
    }

    private void setupWebSocket() {
        try {
            URI uri = new URI(WS_URL);
            webSocketClient = new WebSocketClient(uri) {
                public Map<String, String> getHttpHeaders() {
                    Map<String, String> headers = new HashMap<>();
                    if (currentToken != null) {
                        headers.put("Authorization", "Bearer " + currentToken);
                    }
                    return headers;
                }
    
                @Override
                public void onOpen(ServerHandshake handshakedata) {
                    Log.d(TAG, "WebSocket connected");
                    runOnUiThread(() -> {
                        Toast.makeText(MainActivity.this, "Connected to chat", Toast.LENGTH_SHORT).show();
                    });
                }
    
                @Override
                public void onMessage(String message) {
                    Log.d(TAG, "WebSocket message: " + message);
                    handleWebSocketMessage(message);
                }
    
                @Override
                public void onClose(int code, String reason, boolean remote) {
                    Log.d(TAG, "WebSocket disconnected: " + reason);
                    runOnUiThread(() -> {
                        Toast.makeText(MainActivity.this, "Disconnected from chat", Toast.LENGTH_SHORT).show();
                    });
                }
    
                @Override
                public void onError(Exception ex) {
                    Log.e(TAG, "WebSocket error", ex);
                }
            };
            webSocketClient.connect();
        } catch (Exception e) {
            Log.e(TAG, "WebSocket setup error", e);
            Toast.makeText(this, "WebSocket connection failed", Toast.LENGTH_SHORT).show();
        }
    }

    private void handleWebSocketMessage(String message) {
        try {
            JSONObject json = new JSONObject(message);
            String type = json.optString("type");

            if ("message".equals(type) && "new".equals(json.optString("action"))) {
                String messageChannel = json.optString("channel");
                if (currentChannel != null && currentChannel.equals(messageChannel)) {
                    Message newMessage = new Message(
                            json.optString("id"),
                            json.optString("from"),
                            json.optString("text"),
                            json.optLong("ts"),
                            messageChannel
                    );
                    runOnUiThread(() -> {
                        messages.add(newMessage);
                        messageAdapter.notifyDataSetChanged();
                        if (messages.size() > 0) {
                            lvMessages.smoothScrollToPosition(messages.size() - 1);
                        }
                    });
                }
            }
        } catch (JSONException e) {
            Log.e(TAG, "WebSocket message parse error", e);
        }
    }

    private void toggleVoiceRecording() {
        if (!isRecording) {
            startRecording();
        } else {
            stopRecording();
        }
    }

    private void startRecording() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) 
                != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, 
                    new String[]{Manifest.permission.RECORD_AUDIO}, PERMISSION_REQUEST_CODE);
            return;
        }

        try {
            mediaRecorder = new MediaRecorder();
            mediaRecorder.setAudioSource(MediaRecorder.AudioSource.MIC);
            mediaRecorder.setOutputFormat(MediaRecorder.OutputFormat.THREE_GPP);
            mediaRecorder.setAudioEncoder(MediaRecorder.AudioEncoder.AMR_NB);

            audioFilePath = getExternalFilesDir(Environment.DIRECTORY_MUSIC) + "/voice_message.3gp";
            mediaRecorder.setOutputFile(audioFilePath);

            mediaRecorder.prepare();
            mediaRecorder.start();
            isRecording = true;
            btnRecordVoice.setText("Stop Recording");
            Toast.makeText(this, "Recording started", Toast.LENGTH_SHORT).show();
        } catch (Exception e) {
            Log.e(TAG, "Voice recording start error", e);
            Toast.makeText(this, "Recording failed", Toast.LENGTH_SHORT).show();
            cleanupMediaRecorder();
        }
    }

    private void stopRecording() {
        try {
            if (mediaRecorder != null) {
                mediaRecorder.stop();
            }
        } catch (Exception e) {
            Log.e(TAG, "MediaRecorder stop error", e);
        } finally {
            cleanupMediaRecorder();
        }
        
        isRecording = false;
        btnRecordVoice.setText("Record Voice");
        Toast.makeText(this, "Recording stopped", Toast.LENGTH_SHORT).show();

        uploadVoiceMessage();
    }

    private void cleanupMediaRecorder() {
        if (mediaRecorder != null) {
            try {
                mediaRecorder.release();
            } catch (Exception e) {
                Log.e(TAG, "MediaRecorder release error", e);
            }
            mediaRecorder = null;
        }
    }

    private void uploadVoiceMessage() {
        new AsyncTask<Void, Void, String>() {
            @Override
            protected String doInBackground(Void... voids) {
                try {
                    JSONObject payload = new JSONObject();
                    payload.put("channel", currentChannel);
                    payload.put("duration", 0);

                    JSONObject result = sendPostRequest("/api/voice/upload", payload);
                    if (result != null && result.optBoolean("success")) {
                        return result.optString("voiceId");
                    }
                } catch (Exception e) {
                    Log.e(TAG, "Voice upload request error", e);
                }
                return null;
            }

            @Override
            protected void onPostExecute(String voiceId) {
                if (voiceId != null) {
                    uploadVoiceFile(voiceId);
                } else {
                    Toast.makeText(MainActivity.this, "Voice upload failed", Toast.LENGTH_SHORT).show();
                }
            }
        }.execute();
    }

    private void uploadVoiceFile(String voiceId) {
        new AsyncTask<String, Void, Boolean>() {
            @Override
            protected Boolean doInBackground(String... params) {
                String voiceId = params[0];
                try {
                    File audioFile = new File(audioFilePath);
                    if (!audioFile.exists()) {
                        return false;
                    }

                    URL url = new URL(SERVER_URL + "/api/upload/voice/" + voiceId);
                    HttpURLConnection conn = (HttpURLConnection) url.openConnection();
                    conn.setRequestMethod("POST");
                    conn.setRequestProperty("Authorization", "Bearer " + currentToken);
                    conn.setRequestProperty("Content-Type", "audio/3gpp");
                    conn.setDoOutput(true);
                    conn.setChunkedStreamingMode(1024);

                    try (FileInputStream fis = new FileInputStream(audioFile);
                         DataOutputStream dos = new DataOutputStream(conn.getOutputStream())) {
                        
                        byte[] buffer = new byte[1024];
                        int bytesRead;
                        while ((bytesRead = fis.read(buffer)) != -1) {
                            dos.write(buffer, 0, bytesRead);
                        }
                    }

                    int responseCode = conn.getResponseCode();
                    return responseCode == 200;
                } catch (Exception e) {
                    Log.e(TAG, "Voice file upload error", e);
                    return false;
                }
            }

            @Override
            protected void onPostExecute(Boolean success) {
                if (success) {
                    sendVoiceMessage(voiceId);
                } else {
                    Toast.makeText(MainActivity.this, "Voice file upload failed", Toast.LENGTH_SHORT).show();
                }
            }
        }.execute(voiceId);
    }

    private void sendVoiceMessage(String voiceId) {
        new AsyncTask<String, Void, JSONObject>() {
            @Override
            protected JSONObject doInBackground(String... params) {
                try {
                    JSONObject payload = new JSONObject();
                    payload.put("channel", currentChannel);
                    payload.put("text", "Voice message");
                    payload.put("voiceMessage", params[0]);

                    return sendPostRequest("/api/message", payload);
                } catch (Exception e) {
                    Log.e(TAG, "Send voice message error", e);
                    return null;
                }
            }

            @Override
            protected void onPostExecute(JSONObject result) {
                if (result != null && result.optBoolean("success")) {
                    Toast.makeText(MainActivity.this, "Voice message sent", Toast.LENGTH_SHORT).show();
                    loadMessages();
                } else {
                    Toast.makeText(MainActivity.this, "Failed to send voice message", Toast.LENGTH_SHORT).show();
                }
            }
        }.execute(voiceId);
    }

    private JSONObject sendPostRequest(String endpoint, JSONObject payload) throws IOException {
        HttpURLConnection conn = null;
        try {
            URL url = new URL(SERVER_URL + endpoint);
            conn = (HttpURLConnection) url.openConnection();
            conn.setRequestMethod("POST");
            conn.setRequestProperty("Content-Type", "application/json");
            conn.setRequestProperty("Accept", "application/json");
            conn.setConnectTimeout(10000);
            conn.setReadTimeout(10000);
            
            if (currentToken != null) {
                conn.setRequestProperty("Authorization", "Bearer " + currentToken);
            }
            
            conn.setDoOutput(true);
            try (java.io.OutputStream os = conn.getOutputStream()) {
                os.write(payload.toString().getBytes("UTF-8"));
            }

            int responseCode = conn.getResponseCode();
            if (responseCode == 200) {
                BufferedReader reader = new BufferedReader(new InputStreamReader(conn.getInputStream()));
                StringBuilder response = new StringBuilder();
                String line;
                while ((line = reader.readLine()) != null) {
                    response.append(line);
                }
                return new JSONObject(response.toString());
            } else {
                Log.e(TAG, "POST request failed: " + responseCode);
                BufferedReader reader = new BufferedReader(new InputStreamReader(conn.getErrorStream()));
                StringBuilder errorResponse = new StringBuilder();
                String line;
                while ((line = reader.readLine()) != null) {
                    errorResponse.append(line);
                }
                Log.e(TAG, "Error response: " + errorResponse.toString());
            }
        } catch (Exception e) {
            throw new IOException("Request failed", e);
        } finally {
            if (conn != null) conn.disconnect();
        }
        return null;
    }

    private JSONObject sendGetRequest(String urlString) throws IOException {
        HttpURLConnection conn = null;
        try {
            URL url = new URL(urlString);
            conn = (HttpURLConnection) url.openConnection();
            conn.setRequestMethod("GET");
            conn.setConnectTimeout(10000);
            conn.setReadTimeout(10000);
            if (currentToken != null) {
                conn.setRequestProperty("Authorization", "Bearer " + currentToken);
            }

            int responseCode = conn.getResponseCode();
            if (responseCode == 200) {
                BufferedReader reader = new BufferedReader(new InputStreamReader(conn.getInputStream()));
                StringBuilder response = new StringBuilder();
                String line;
                while ((line = reader.readLine()) != null) {
                    response.append(line);
                }
                return new JSONObject(response.toString());
            } else {
                Log.e(TAG, "GET request failed: " + responseCode);
            }
        } catch (Exception e) {
            throw new IOException("Request failed", e);
        } finally {
            if (conn != null) conn.disconnect();
        }
        return null;
    }

    private Bitmap downloadImage(String urlString) throws IOException {
        HttpURLConnection conn = null;
        try {
            URL url = new URL(urlString);
            conn = (HttpURLConnection) url.openConnection();
            conn.setConnectTimeout(10000);
            conn.setReadTimeout(10000);
            conn.connect();

            InputStream input = conn.getInputStream();
            return BitmapFactory.decodeStream(input);
        } finally {
            if (conn != null) conn.disconnect();
        }
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (webSocketClient != null) {
            webSocketClient.close();
        }
        if (scheduler != null && !scheduler.isShutdown()) {
            scheduler.shutdown();
        }
        cleanupMediaRecorder();
        if (mediaPlayer != null) {
            mediaPlayer.release();
            mediaPlayer = null;
        }
    }

    private class Message {
        String id;
        String from;
        String text;
        long timestamp;
        String channel;

        Message(String id, String from, String text, long timestamp, String channel) {
            this.id = id;
            this.from = from;
            this.text = text;
            this.timestamp = timestamp;
            this.channel = channel;
        }
    }

    private class MessageAdapter extends ArrayAdapter<Message> {
        MessageAdapter() {
            super(MainActivity.this, R.layout.message_item, messages);
        }

        @NonNull
        @Override
        public View getView(int position, View convertView, @NonNull ViewGroup parent) {
            View view = convertView;
            if (view == null) {
                view = getLayoutInflater().inflate(R.layout.message_item, parent, false);
            }

            Message message = messages.get(position);
            TextView tvSender = view.findViewById(R.id.tvSender);
            TextView tvMessage = view.findViewById(R.id.tvMessage);
            TextView tvTime = view.findViewById(R.id.tvTime);

            tvSender.setText(message.from);
            tvMessage.setText(message.text);
            tvTime.setText(new SimpleDateFormat("HH:mm", Locale.getDefault())
                    .format(new Date(message.timestamp)));

            return view;
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == PERMISSION_REQUEST_CODE) {
            for (int i = 0; i < permissions.length; i++) {
                if (permissions[i].equals(Manifest.permission.RECORD_AUDIO) && grantResults[i] == PackageManager.PERMISSION_GRANTED) {
                    Toast.makeText(this, "Microphone permission granted", Toast.LENGTH_SHORT).show();
                }
            }
        }
    }
}
