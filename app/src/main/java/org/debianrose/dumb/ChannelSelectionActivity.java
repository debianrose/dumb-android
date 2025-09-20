package org.debianrose.dumb;

import android.content.Intent;
import android.os.AsyncTask;
import android.os.Bundle;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ListView;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

public class ChannelSelectionActivity extends AppCompatActivity {

    private ListView lvChannels;
    private EditText etChannel;
    private Button btnJoinChannel, btnCreateChannel;
    private ArrayAdapter<String> channelAdapter;
    private List<Channel> channels = new ArrayList<>();
    private String currentToken;
    private String currentUser;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_channel_selection);

        currentToken = getIntent().getStringExtra("token");
        currentUser = getIntent().getStringExtra("username");

        lvChannels = findViewById(R.id.lvChannels);
        etChannel = findViewById(R.id.etChannel);
        btnJoinChannel = findViewById(R.id.btnJoinChannel);
        btnCreateChannel = findViewById(R.id.btnCreateChannel);

        channelAdapter = new ArrayAdapter<>(this, android.R.layout.simple_list_item_1, getChannelDisplayNames());
        lvChannels.setAdapter(channelAdapter);

        btnJoinChannel.setOnClickListener(v -> joinChannel());
        btnCreateChannel.setOnClickListener(v -> createChannel());
        lvChannels.setOnItemClickListener((parent, view, position, id) -> {
            Channel channel = channels.get(position);
            openChat(channel);
        });

        loadChannels();
    }

    private List<String> getChannelDisplayNames() {
        List<String> names = new ArrayList<>();
        for (Channel channel : channels) {
            names.add(channel.name + " (ID: " + channel.id + ")");
        }
        return names;
    }

    private void loadChannels() {
        new AsyncTask<Void, Void, JSONObject>() {
            @Override
            protected JSONObject doInBackground(Void... voids) {
                try {
                    return NetworkUtils.sendGetRequest("/api/channels", currentToken);
                } catch (Exception e) {
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
                                Channel channel = new Channel(
                                        channelObj.optString("id"),
                                        channelObj.optString("name"),
                                        channelObj.optString("owner")
                                );
                                channels.add(channel);
                            }
                        }
                    }
                    channelAdapter.clear();
                    channelAdapter.addAll(getChannelDisplayNames());
                    channelAdapter.notifyDataSetChanged();
                } else {
                    Toast.makeText(ChannelSelectionActivity.this, "Failed to load channels", Toast.LENGTH_SHORT).show();
                }
            }
        }.execute();
    }

    private void joinChannel() {
        String channelInput = etChannel.getText().toString().trim();
        if (channelInput.isEmpty()) {
            Toast.makeText(this, "Please enter channel ID or name", Toast.LENGTH_SHORT).show();
            return;
        }

        // Пытаемся найти канал по ID или имени
        Channel targetChannel = findChannelByIdOrName(channelInput);
        if (targetChannel == null) {
            Toast.makeText(this, "Channel not found: " + channelInput, Toast.LENGTH_SHORT).show();
            return;
        }

        joinChannelById(targetChannel.id);
    }

    private Channel findChannelByIdOrName(String input) {
        for (Channel channel : channels) {
            if (channel.id.equals(input) || channel.name.equals(input)) {
                return channel;
            }
        }
        return null;
    }

    private void joinChannelById(String channelId) {
        new AsyncTask<Void, Void, JSONObject>() {
            @Override
            protected JSONObject doInBackground(Void... voids) {
                try {
                    JSONObject payload = new JSONObject();
                    payload.put("channel", channelId); // Теперь отправляем ID канала
                    return NetworkUtils.sendPostRequest("/api/channels/join", payload, currentToken);
                } catch (Exception e) {
                    return null;
                }
            }

            @Override
            protected void onPostExecute(JSONObject result) {
                if (result != null && result.optBoolean("success")) {
                    loadChannels(); // Перезагружаем список каналов
                    etChannel.setText("");
                    Toast.makeText(ChannelSelectionActivity.this, "Successfully joined channel", Toast.LENGTH_SHORT).show();
                } else {
                    String error = result != null ? result.optString("error", "Failed to join channel") : "Failed to join channel";
                    Toast.makeText(ChannelSelectionActivity.this, error, Toast.LENGTH_SHORT).show();
                }
            }
        }.execute();
    }

    private void createChannel() {
        String channelName = etChannel.getText().toString().trim();
        if (channelName.isEmpty()) {
            Toast.makeText(this, "Please enter channel name", Toast.LENGTH_SHORT).show();
            return;
        }

        new AsyncTask<Void, Void, JSONObject>() {
            @Override
            protected JSONObject doInBackground(Void... voids) {
                try {
                    JSONObject payload = new JSONObject();
                    payload.put("name", channelName);
                    return NetworkUtils.sendPostRequest("/api/channels/create", payload, currentToken);
                } catch (Exception e) {
                    return null;
                }
            }

            @Override
            protected void onPostExecute(JSONObject result) {
                if (result != null && result.optBoolean("success")) {
                    String channelId = result.optString("channelId");
                    if (channelId != null) {
                        // Автоматически присоединяемся к созданному каналу
                        joinChannelById(channelId);
                    } else {
                        loadChannels();
                    }
                    etChannel.setText("");
                    Toast.makeText(ChannelSelectionActivity.this, "Channel created: " + channelName, Toast.LENGTH_SHORT).show();
                } else {
                    String error = result != null ? result.optString("error", "Failed to create channel") : "Failed to create channel";
                    Toast.makeText(ChannelSelectionActivity.this, error, Toast.LENGTH_SHORT).show();
                }
            }
        }.execute();
    }

    private void openChat(Channel channel) {
        // Сначала присоединяемся к каналу, потом открываем чат
        joinChannelByIdAndOpen(channel.id, channel.name);
    }

    private void joinChannelByIdAndOpen(String channelId, String channelName) {
        new AsyncTask<Void, Void, JSONObject>() {
            @Override
            protected JSONObject doInBackground(Void... voids) {
                try {
                    JSONObject payload = new JSONObject();
                    payload.put("channel", channelId);
                    return NetworkUtils.sendPostRequest("/api/channels/join", payload, currentToken);
                } catch (Exception e) {
                    return null;
                }
            }

            @Override
            protected void onPostExecute(JSONObject result) {
                if (result != null && result.optBoolean("success")) {
                    Intent intent = new Intent(ChannelSelectionActivity.this, ChatActivity.class);
                    intent.putExtra("token", currentToken);
                    intent.putExtra("username", currentUser);
                    intent.putExtra("channelId", channelId);
                    intent.putExtra("channelName", channelName);
                    startActivity(intent);
                } else {
                    String error = result != null ? result.optString("error", "Failed to join channel") : "Failed to join channel";
                    Toast.makeText(ChannelSelectionActivity.this, error, Toast.LENGTH_SHORT).show();
                }
            }
        }.execute();
    }
}
