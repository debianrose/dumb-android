package org.debianrose.dumb;

import android.Manifest;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.media.MediaPlayer;
import android.media.MediaRecorder;
import android.os.AsyncTask;
import android.os.Bundle;
import android.os.Environment;
import android.os.Handler;
import android.text.TextUtils;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ListView;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;
import androidx.core.content.ContextCompat;

import org.java_websocket.client.WebSocketClient;
import org.java_websocket.handshake.ServerHandshake;
import org.json.JSONArray;
import org.json.JSONObject;

import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.net.URL;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class ChatActivity extends AppCompatActivity {

    private EditText etMessage;
    private Button btnSend, btnRecordVoice, btnStartCall;
    private ListView lvMessages;
    private MessageAdapter messageAdapter;
    private List<Message> messages = new ArrayList<>();

    private WebSocketClient webSocketClient;
    private MediaRecorder mediaRecorder;
    private MediaPlayer mediaPlayer;
    private String audioFilePath;
    private boolean isRecording = false;

    private String currentToken;
    private String currentUser;
    private String currentChannelId;
    private String currentChannelName;

    private Handler messageRefreshHandler = new Handler();
    private Handler voiceProgressHandler = new Handler();
    private static final long MESSAGE_REFRESH_INTERVAL = 3000;
    
    private String currentPlayingMessageId = null;
    private int voiceDuration = 0;
    private int currentPosition = 0;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_chat);

        currentToken = getIntent().getStringExtra("token");
        currentUser = getIntent().getStringExtra("username");
        currentChannelId = getIntent().getStringExtra("channelId");
        currentChannelName = getIntent().getStringExtra("channelName");

        setTitle(currentChannelName);

        etMessage = findViewById(R.id.etMessage);
        btnSend = findViewById(R.id.btnSend);
        btnRecordVoice = findViewById(R.id.btnRecordVoice);
        btnStartCall = findViewById(R.id.btnStartCall);
        lvMessages = findViewById(R.id.lvMessages);

        messageAdapter = new MessageAdapter(this, messages);
        lvMessages.setAdapter(messageAdapter);

        btnSend.setOnClickListener(v -> sendMessage());
        btnRecordVoice.setOnClickListener(v -> toggleVoiceRecording());
        btnStartCall.setOnClickListener(v -> startVoiceCall());

        loadMessages();
        startMessageRefresh();
        loadChannelMembers();
    }

    private void startVoiceCall() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO}, 200);
            return;
        }
        
        showUserSelectionDialog();
    }

    private void showUserSelectionDialog() {
        new AsyncTask<Void, Void, JSONObject>() {
            @Override
            protected JSONObject doInBackground(Void... voids) {
                try {
                    return NetworkUtils.sendGetRequest("/api/channels/members?channel=" + currentChannelId, currentToken);
                } catch (Exception e) {
                    return null;
                }
            }

            @Override
            protected void onPostExecute(JSONObject result) {
                if (result != null && result.optBoolean("success")) {
                    JSONArray membersArray = result.optJSONArray("members");
                    if (membersArray != null && membersArray.length() > 1) {
                        List<String> otherUsers = new ArrayList<>();
                        for (int i = 0; i < membersArray.length(); i++) {
                            String user = membersArray.optString(i);
                            if (!user.equals(currentUser)) {
                                otherUsers.add(user);
                            }
                        }
                        
                        if (!otherUsers.isEmpty()) {
                            showUsersListDialog(otherUsers);
                        } else {
                            Toast.makeText(ChatActivity.this, "No other users in channel", Toast.LENGTH_SHORT).show();
                        }
                    } else {
                        Toast.makeText(ChatActivity.this, "No other users in channel", Toast.LENGTH_SHORT).show();
                    }
                } else {
                    Toast.makeText(ChatActivity.this, "Failed to load channel members", Toast.LENGTH_SHORT).show();
                }
            }
        }.execute();
    }

    private void showUsersListDialog(List<String> users) {
        CharSequence[] userArray = users.toArray(new CharSequence[0]);
        
        androidx.appcompat.app.AlertDialog.Builder builder = new androidx.appcompat.app.AlertDialog.Builder(this);
        builder.setTitle("Select user to call");
        builder.setItems(userArray, (dialog, which) -> {
            String targetUser = users.get(which);
            initiateCallWithUser(targetUser);
        });
        builder.show();
    }

    private void initiateCallWithUser(String targetUser) {
        new AsyncTask<String, Void, JSONObject>() {
            @Override
            protected JSONObject doInBackground(String... params) {
                try {
                    JSONObject payload = new JSONObject();
                    payload.put("toUser", params[0]);
                    payload.put("channel", currentChannelId);
                    payload.put("offer", "dummy-offer-sdp");

                    return NetworkUtils.sendPostRequest("/api/webrtc/offer", payload, currentToken);
                } catch (Exception e) {
                    return null;
                }
            }

            @Override
            protected void onPostExecute(JSONObject result) {
                if (result != null && result.optBoolean("success")) {
                    openVoiceCallActivity(targetUser);
                } else {
                    String error = result != null ? result.optString("error", "Call failed") : "Call failed";
                    Toast.makeText(ChatActivity.this, error, Toast.LENGTH_SHORT).show();
                }
            }
        }.execute(targetUser);
    }

    private void openVoiceCallActivity(String targetUser) {
        Intent intent = new Intent(this, VoiceCallActivity.class);
        intent.putExtra("token", currentToken);
        intent.putExtra("username", currentUser);
        intent.putExtra("targetUser", targetUser);
        intent.putExtra("channelId", currentChannelId);
        startActivity(intent);
    }

    private void loadChannelMembers() {
        new AsyncTask<Void, Void, JSONObject>() {
            @Override
            protected JSONObject doInBackground(Void... voids) {
                try {
                    return NetworkUtils.sendGetRequest("/api/channels/members?channel=" + currentChannelId, currentToken);
                } catch (Exception e) {
                    return null;
                }
            }

            @Override
            protected void onPostExecute(JSONObject result) {
                if (result != null && result.optBoolean("success")) {
                    JSONArray membersArray = result.optJSONArray("members");
                    if (membersArray != null && membersArray.length() > 1) {
                        btnStartCall.setVisibility(View.VISIBLE);
                    } else {
                        btnStartCall.setVisibility(View.GONE);
                    }
                }
            }
        }.execute();
    }

    public void toggleVoiceMessage(Message message) {
        if (currentPlayingMessageId != null && currentPlayingMessageId.equals(message.id)) {
            stopVoicePlayback();
        } else {
            playVoiceMessage(message);
        }
    }

    public boolean isVoicePlaying(String messageId) {
        return currentPlayingMessageId != null && currentPlayingMessageId.equals(messageId);
    }

    public int getVoiceProgress(String messageId) {
        if (currentPlayingMessageId != null && currentPlayingMessageId.equals(messageId) && voiceDuration > 0) {
            return (int) ((currentPosition * 100) / voiceDuration);
        }
        return 0;
    }

    private void playVoiceMessage(Message message) {
        if (message.voice == null) return;
        
        stopVoicePlayback();
        
        currentPlayingMessageId = message.id;
        voiceDuration = message.voice.duration * 1000;
        
        new AsyncTask<Message, Void, String>() {
            @Override
            protected String doInBackground(Message... params) {
                try {
                    String downloadUrl = "http://95.81.122.186:3000" + params[0].voice.downloadUrl;
                    return downloadVoiceMessage(downloadUrl);
                } catch (Exception e) {
                    return null;
                }
            }

            @Override
            protected void onPostExecute(String filePath) {
                if (filePath != null) {
                    startVoicePlayback(filePath);
                } else {
                    Toast.makeText(ChatActivity.this, "Failed to download voice message", Toast.LENGTH_SHORT).show();
                    currentPlayingMessageId = null;
                }
            }
        }.execute(message);
    }

    private void startVoicePlayback(String filePath) {
        try {
            mediaPlayer = new MediaPlayer();
            mediaPlayer.setDataSource(filePath);
            mediaPlayer.prepare();
            mediaPlayer.start();
            
            mediaPlayer.setOnCompletionListener(mp -> {
                stopVoicePlayback();
                messageAdapter.notifyDataSetChanged();
            });
            
            startVoiceProgressUpdater();
            messageAdapter.notifyDataSetChanged();
            
        } catch (Exception e) {
            Toast.makeText(this, "Playback failed", Toast.LENGTH_SHORT).show();
            currentPlayingMessageId = null;
        }
    }

    private void startVoiceProgressUpdater() {
        voiceProgressHandler.postDelayed(new Runnable() {
            @Override
            public void run() {
                if (mediaPlayer != null && mediaPlayer.isPlaying()) {
                    currentPosition = mediaPlayer.getCurrentPosition();
                    messageAdapter.notifyDataSetChanged();
                    voiceProgressHandler.postDelayed(this, 100);
                }
            }
        }, 100);
    }

    private void stopVoicePlayback() {
        if (mediaPlayer != null) {
            mediaPlayer.stop();
            mediaPlayer.release();
            mediaPlayer = null;
        }
        voiceProgressHandler.removeCallbacksAndMessages(null);
        currentPlayingMessageId = null;
        currentPosition = 0;
        messageAdapter.notifyDataSetChanged();
    }

    private String downloadVoiceMessage(String urlString) throws Exception {
        URL url = new URL(urlString);
        HttpURLConnection connection = (HttpURLConnection) url.openConnection();
        connection.setRequestMethod("GET");
        connection.setRequestProperty("Authorization", "Bearer " + currentToken);
        
        String filePath = getExternalFilesDir(Environment.DIRECTORY_MUSIC) + "/voice_" + System.currentTimeMillis() + ".ogg";
        InputStream input = connection.getInputStream();
        FileOutputStream output = new FileOutputStream(filePath);
        
        byte[] buffer = new byte[4096];
        int bytesRead;
        while ((bytesRead = input.read(buffer)) != -1) {
            output.write(buffer, 0, bytesRead);
        }
        
        output.close();
        input.close();
        connection.disconnect();
        
        return filePath;
    }

    private void startMessageRefresh() {
        messageRefreshHandler.postDelayed(new Runnable() {
            @Override
            public void run() {
                if (!isFinishing()) {
                    loadMessages();
                    messageRefreshHandler.postDelayed(this, MESSAGE_REFRESH_INTERVAL);
                }
            }
        }, MESSAGE_REFRESH_INTERVAL);
    }

    private void loadMessages() {
        new AsyncTask<Void, Void, JSONObject>() {
            @Override
            protected JSONObject doInBackground(Void... voids) {
                try {
                    return NetworkUtils.sendGetRequest("/api/messages?channel=" + currentChannelId + "&limit=100", currentToken);
                } catch (Exception e) {
                    return null;
                }
            }

            @Override
            protected void onPostExecute(JSONObject result) {
                if (result != null && result.optBoolean("success")) {
                    List<Message> newMessages = new ArrayList<>();
                    JSONArray messagesArray = result.optJSONArray("messages");
                    if (messagesArray != null) {
                        for (int i = 0; i < messagesArray.length(); i++) {
                            JSONObject msgObj = messagesArray.optJSONObject(i);
                            if (msgObj != null) {
                                Message message = createMessageFromJson(msgObj);
                                newMessages.add(message);
                            }
                        }
                    }
                    
                    if (newMessages.size() != messages.size() || !messages.equals(newMessages)) {
                        messages.clear();
                        messages.addAll(newMessages);
                        messageAdapter.notifyDataSetChanged();
                        if (!messages.isEmpty()) {
                            lvMessages.smoothScrollToPosition(messages.size() - 1);
                        }
                    }
                }
            }
        }.execute();
    }

    private Message createMessageFromJson(JSONObject msgObj) {
        String id = msgObj.optString("id");
        String from = msgObj.optString("from");
        String text = msgObj.optString("text");
        long timestamp = msgObj.optLong("ts");
        String channel = msgObj.optString("channel");
        
        JSONObject voiceObj = msgObj.optJSONObject("voice");
        if (voiceObj != null) {
            String filename = voiceObj.optString("filename");
            int duration = voiceObj.optInt("duration");
            String downloadUrl = voiceObj.optString("downloadUrl");
            
            Message.VoiceAttachment voiceAttachment = new Message.VoiceAttachment(filename, duration, downloadUrl);
            return new Message(id, from, text, timestamp, channel, voiceAttachment);
        }
        
        return new Message(id, from, text, timestamp, channel);
    }

    private void sendMessage() {
        String text = etMessage.getText().toString().trim();
        if (TextUtils.isEmpty(text)) {
            Toast.makeText(this, "Please enter message", Toast.LENGTH_SHORT).show();
            return;
        }

        new AsyncTask<Void, Void, JSONObject>() {
            @Override
            protected JSONObject doInBackground(Void... voids) {
                try {
                    JSONObject payload = new JSONObject();
                    payload.put("channel", currentChannelId);
                    payload.put("text", text);
                    return NetworkUtils.sendPostRequest("/api/message", payload, currentToken);
                } catch (Exception e) {
                    runOnUiThread(() -> {
                        Toast.makeText(ChatActivity.this, "Send error: " + e.getMessage(), Toast.LENGTH_SHORT).show();
                    });
                    return null;
                }
            }

            @Override
            protected void onPostExecute(JSONObject result) {
                if (result != null && result.optBoolean("success")) {
                    etMessage.setText("");
                    loadMessages();
                } else {
                    String error = result != null ? result.optString("error", "Failed to send message") : "Failed to send message";
                    Toast.makeText(ChatActivity.this, error, Toast.LENGTH_SHORT).show();
                }
            }
        }.execute();
    }

    private void toggleVoiceRecording() {
        if (!isRecording) {
            startRecording();
        } else {
            stopRecording();
        }
    }

    private void startRecording() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO}, 100);
            return;
        }

        try {
            mediaRecorder = new MediaRecorder();
            mediaRecorder.setAudioSource(MediaRecorder.AudioSource.MIC);
            mediaRecorder.setOutputFormat(MediaRecorder.OutputFormat.OGG);
            mediaRecorder.setAudioEncoder(MediaRecorder.AudioEncoder.OPUS);
            mediaRecorder.setAudioSamplingRate(48000);
            mediaRecorder.setAudioEncodingBitRate(96000);

            audioFilePath = getExternalFilesDir(Environment.DIRECTORY_MUSIC) + "/voice_message.ogg";
            mediaRecorder.setOutputFile(audioFilePath);

            mediaRecorder.prepare();
            mediaRecorder.start();
            isRecording = true;
            btnRecordVoice.setText("Stop Recording");
            Toast.makeText(this, "Recording started", Toast.LENGTH_SHORT).show();
        } catch (Exception e) {
            cleanupMediaRecorder();
            Toast.makeText(this, "Recording failed", Toast.LENGTH_SHORT).show();
        }
    }

    private void stopRecording() {
        try {
            if (mediaRecorder != null) {
                mediaRecorder.stop();
            }
        } catch (Exception e) {
            e.printStackTrace();
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
                e.printStackTrace();
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
                    payload.put("channel", currentChannelId);
                    payload.put("duration", 5);

                    JSONObject result = NetworkUtils.sendPostRequest("/api/voice/upload", payload, currentToken);
                    if (result != null && result.optBoolean("success")) {
                        return result.optString("voiceId");
                    }
                } catch (Exception e) {
                }
                return null;
            }

            @Override
            protected void onPostExecute(String voiceId) {
                if (voiceId != null) {
                    uploadVoiceFile(voiceId);
                } else {
                    Toast.makeText(ChatActivity.this, "Voice upload failed", Toast.LENGTH_SHORT).show();
                }
            }
        }.execute();
    }

    private void uploadVoiceFile(String voiceId) {
        new AsyncTask<String, Void, Boolean>() {
            @Override
            protected Boolean doInBackground(String... params) {
                try {
                    String uploadUrl = "http://95.81.122.186:3000/api/upload/voice/" + params[0];
                    URL url = new URL(uploadUrl);
                    HttpURLConnection connection = (HttpURLConnection) url.openConnection();
                    connection.setRequestMethod("POST");
                    connection.setRequestProperty("Authorization", "Bearer " + currentToken);
                    connection.setRequestProperty("Content-Type", "audio/ogg");
                    connection.setDoOutput(true);
                    
                    FileInputStream fileInputStream = new FileInputStream(audioFilePath);
                    OutputStream outputStream = connection.getOutputStream();
                    
                    byte[] buffer = new byte[4096];
                    int bytesRead;
                    while ((bytesRead = fileInputStream.read(buffer)) != -1) {
                        outputStream.write(buffer, 0, bytesRead);
                    }
                    
                    outputStream.close();
                    fileInputStream.close();
                    
                    int responseCode = connection.getResponseCode();
                    return responseCode == 200;
                    
                } catch (Exception e) {
                    return false;
                }
            }

            @Override
            protected void onPostExecute(Boolean success) {
                if (success) {
                    sendVoiceMessage(voiceId);
                } else {
                    Toast.makeText(ChatActivity.this, "Voice file upload failed", Toast.LENGTH_SHORT).show();
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
                    payload.put("channel", currentChannelId);
                    payload.put("text", "Voice message");
                    payload.put("voiceMessage", params[0]);
                    return NetworkUtils.sendPostRequest("/api/message", payload, currentToken);
                } catch (Exception e) {
                    return null;
                }
            }

            @Override
            protected void onPostExecute(JSONObject result) {
                if (result != null && result.optBoolean("success")) {
                    Toast.makeText(ChatActivity.this, "Voice message sent", Toast.LENGTH_SHORT).show();
                    loadMessages();
                } else {
                    Toast.makeText(ChatActivity.this, "Failed to send voice message", Toast.LENGTH_SHORT).show();
                }
            }
        }.execute(voiceId);
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        messageRefreshHandler.removeCallbacksAndMessages(null);
        voiceProgressHandler.removeCallbacksAndMessages(null);
        stopVoicePlayback();
        
        if (webSocketClient != null) {
            webSocketClient.close();
            webSocketClient = null;
        }
        
        cleanupMediaRecorder();
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == 100) {
            if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                Toast.makeText(this, "Microphone permission granted", Toast.LENGTH_SHORT).show();
            }
        } else if (requestCode == 200) {
            if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                showUserSelectionDialog();
            }
        }
    }
}
