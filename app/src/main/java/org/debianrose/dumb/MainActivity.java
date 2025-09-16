package org.debianrose.dumb;

import androidx.appcompat.app.AppCompatActivity;
import android.os.Bundle;
import android.content.Intent;
import android.content.SharedPreferences;

public class MainActivity extends AppCompatActivity {
    
    private SharedPreferences prefs;
    
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        
        prefs = getSharedPreferences("chat_app", MODE_PRIVATE);
        String token = prefs.getString("token", null);
        
        if (token != null) {
            startActivity(new Intent(this, ChatActivity.class));
            finish();
        } else {
            setContentView(R.layout.activity_main);
            setupLoginUI();
        }
    }
    
    private void setupLoginUI() {
        findViewById(R.id.btn_login).setOnClickListener(v -> {
            String username = "test";
            String password = "test";
            
            new Thread(() -> {
                ApiResponse response = ApiClient.login(username, password, null);
                if (response.success && response.token != null) {
                    prefs.edit().putString("token", response.token).apply();
                    runOnUiThread(() -> {
                        startActivity(new Intent(MainActivity.this, ChatActivity.class));
                        finish();
                    });
                }
            }).start();
        });
        
        findViewById(R.id.btn_register).setOnClickListener(v -> {
            String username = "test";
            String password = "test";
            
            new Thread(() -> {
                ApiResponse response = ApiClient.register(username, password);
            }).start();
        });
    }
}
