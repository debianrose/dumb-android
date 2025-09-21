package org.debianrose.dumb;

import android.content.Intent;
import android.os.AsyncTask;
import android.os.Bundle;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
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
    private EditText etChannel, etSearch;
    private Button btnJoinChannel, btnCreateChannel;
    private ArrayAdapter<String> channelAdapter;
    private List<Channel> channels = new ArrayList<>();
    private List<Channel> allChannels = new ArrayList<>();
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
        etSearch = findViewById(R.id.etSearch);
        btnJoinChannel = findViewById(R.id.btnJoinChannel);
        btnCreateChannel = findViewById(R.id.btnCreateChannel);

        channelAdapter = new ArrayAdapter<>(this, android.R.layout.simple_list_item_1, new ArrayList<>());
        lvChannels.setAdapter(channelAdapter);

        btnJoinChannel.setOnClickListener(v -> joinChannel());
        btnCreateChannel.setOnClickListener(v -> createChannel());
        lvChannels.setOnItemClickListener((parent, view, position, id) -> {
            Channel channel = channels.get(position);
            openChat(channel);
        });

        // Добавляем поиск
        etSearch.addTextChangedListener(new TextWatcher() {
            @Override
    public void beforeTextChanged(CharSequence s, int start, int count, int after) {}

            @Override
    public void onTextChanged(CharSequence s, int start, int before, int count) {
                filterChannels(s.toString());
            }

            @Override
    public void afterTextChanged(Editable s) {}
        });

        loadAllChannels();
    }

    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        getMenuInflater().inflate(R.menu.menu_channel_selection, menu);
        return true;
    }

    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        if (item.getItemId() == R.id.menu_2fa_settings) {
            open2FAManagement();
            return true;
        } else if (item.getItemId() == R.id.menu_refresh) {
            loadAllChannels();
            return true;
        }
        return super.onOptionsItemSelected(item);
    }

    private void open2FAManagement() {
        Intent intent = new Intent(this, TwoFAManagementActivity.class);
        intent.putExtra("token", currentToken);
        intent.putExtra("username", currentUser);
        startActivity(intent);
    }

    private void filterChannels(String query) {
        if (query.isEmpty()) {
            channels.clear();
            channels.addAll(allChannels);
        } else {
            channels.clear();
            for (Channel channel : allChannels) {
                if (channel.name.toLowerCase().contains(query.toLowerCase()) ||
                    channel.id.toLowerCase().contains(query.toLowerCase())) {
                    channels.add(channel);
                }
            }
        }
        updateChannelList();
    }

    private void updateChannelList() {
        channelAdapter.clear();
        channelAdapter.addAll(getChannelDisplayNames());
        channelAdapter.notifyDataSetChanged();
    }

    private List<String> getChannelDisplayNames() {
        List<String> names = new ArrayList<>();
        for (Channel channel : channels) {
            names.add(channel.name + " (ID: " + channel.id + ")");
        }
        return names;
    }

    private void loadAllChannels() {
        new AsyncTask<Void, Void, JSONObject>() {
            @Override
            protected JSONObject doInBackground(Void... voids) {
                try {
                    JSONObject payload = new JSONObject();
                    payload.put("query", "%");
                    return NetworkUtils.sendPostRequest("/api/channels/search", payload, currentToken);
                } catch (Exception e) {
                    return null;
                }
            }

            @Override
            protected void onPostExecute(JSONObject result) {
                if (result != null && result.optBoolean("success")) {
                    allChannels.clear();
                    channels.clear();
                    
                    JSONArray channelsArray = result.optJSONArray("channels");
                    if (channelsArray != null) {
                        for (int i = 0; i < channelsArray.length(); i++) {
                            JSONObject channelObj = channelsArray.optJSONObject(i);
                            if (channelObj != null) {
                                Channel channel = new Channel(
                                        channelObj.optString("id"),
                                        channelObj.optString("name"),
                                        channelObj.optString("creator")
                                );
                                allChannels.add(channel);
                                channels.add(channel);
                            }
                        }
                    }
                    
                    updateChannelList();
                    Toast.makeText(ChannelSelectionActivity.this, 
                            "Loaded " + allChannels.size() + " channels", Toast.LENGTH_SHORT).show();
                } else {
                    Toast.makeText(ChannelSelectionActivity.this, 
                            "Failed to load channels", Toast.LENGTH_SHORT).show();
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
        for (Channel channel : allChannels) {
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
                    payload.put("channel", channelId);
                    return NetworkUtils.sendPostRequest("/api/channels/join", payload, currentToken);
                } catch (Exception e) {
                    return null;
                }
            }

            @Override
            protected void onPostExecute(JSONObject result) {
                if (result != null && result.optBoolean("success")) {
                    loadAllChannels(); // Обновляем список после вступления
                    etChannel.setText("");
                    Toast.makeText(ChannelSelectionActivity.this, 
                            "Successfully joined channel", Toast.LENGTH_SHORT).show();
                } else {
                    String error = result != null ? 
                            result.optString("error", "Failed to join channel") : 
                            "Failed to join channel";
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
                        joinChannelById(channelId);
                    } else {
                        loadAllChannels();
                    }
                    etChannel.setText("");
                    Toast.makeText(ChannelSelectionActivity.this, 
                            "Channel created: " + channelName, Toast.LENGTH_SHORT).show();
                } else {
                    String error = result != null ? 
                            result.optString("error", "Failed to create channel") : 
                            "Failed to create channel";
                    Toast.makeText(ChannelSelectionActivity.this, error, Toast.LENGTH_SHORT).show();
                }
            }
        }.execute();
    }

    private void openChat(Channel channel) {
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
                    String error = result != null ? 
                            result.optString("error", "Failed to join channel") : 
                            "Failed to join channel";
                    Toast.makeText(ChannelSelectionActivity.this, error, Toast.LENGTH_SHORT).show();
                }
            }
        }.execute();
    }
}
