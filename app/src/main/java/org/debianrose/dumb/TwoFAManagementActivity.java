package org.debianrose.dumb;

import android.content.Intent;
import android.os.AsyncTask;
import android.os.Bundle;
import android.widget.Button;
import android.widget.CompoundButton;
import android.widget.Switch;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;

import org.json.JSONObject;

public class TwoFAManagementActivity extends AppCompatActivity {

    private Switch switch2FA;
    private Button btnSetup2FA;
    private String currentToken;
    private String currentUser;
    private boolean is2FAEnabled = false;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_2fa_management);

        currentToken = getIntent().getStringExtra("token");
        currentUser = getIntent().getStringExtra("username");

        switch2FA = findViewById(R.id.switch2FA);
        btnSetup2FA = findViewById(R.id.btnSetup2FA);

        load2FAStatus();

        switch2FA.setOnCheckedChangeListener((buttonView, isChecked) -> {
            if (isChecked != is2FAEnabled) {
                if (isChecked) {
                    enable2FA();
                } else {
                    disable2FA();
                }
            }
        });

        btnSetup2FA.setOnClickListener(v -> setup2FA());
    }

    private void load2FAStatus() {
        new AsyncTask<Void, Void, JSONObject>() {
            @Override
            protected JSONObject doInBackground(Void... voids) {
                try {
                    return NetworkUtils.sendGetRequest("/api/2fa/status", currentToken);
                } catch (Exception e) {
                    return null;
                }
            }

            @Override
            protected void onPostExecute(JSONObject result) {
                if (result != null && result.optBoolean("success")) {
                    is2FAEnabled = result.optBoolean("enabled");
                    switch2FA.setChecked(is2FAEnabled);
                    btnSetup2FA.setEnabled(!is2FAEnabled);
                } else {
                    Toast.makeText(TwoFAManagementActivity.this, 
                            "Failed to load 2FA status", Toast.LENGTH_SHORT).show();
                }
            }
        }.execute();
    }

    private void setup2FA() {
        new AsyncTask<Void, Void, JSONObject>() {
            @Override
            protected JSONObject doInBackground(Void... voids) {
                try {
                    return NetworkUtils.sendPostRequest("/api/2fa/setup", new JSONObject(), currentToken);
                } catch (Exception e) {
                    return null;
                }
            }

            @Override
            protected void onPostExecute(JSONObject result) {
                if (result != null && result.optBoolean("success")) {
                    String secret = result.optString("secret");
                    String qrCodeUrl = result.optString("qrCodeUrl");
                    
                    // Показать диалог с QR-кодом и секретом
                    Show2FASetupDialog dialog = new Show2FASetupDialog(
                            TwoFAManagementActivity.this, 
                            secret, 
                            qrCodeUrl,
                            (token) -> verify2FASetup(token)
                    );
                    dialog.show();
                } else {
                    Toast.makeText(TwoFAManagementActivity.this, 
                            "Failed to setup 2FA", Toast.LENGTH_SHORT).show();
                }
            }
        }.execute();
    }

    private void verify2FASetup(String token) {
        new AsyncTask<String, Void, JSONObject>() {
            @Override
            protected JSONObject doInBackground(String... tokens) {
                try {
                    JSONObject payload = new JSONObject();
                    payload.put("token", tokens[0]);
                    return NetworkUtils.sendPostRequest("/api/2fa/enable", payload, currentToken);
                } catch (Exception e) {
                    return null;
                }
            }

            @Override
            protected void onPostExecute(JSONObject result) {
                if (result != null && result.optBoolean("success")) {
                    Toast.makeText(TwoFAManagementActivity.this, 
                            "2FA enabled successfully", Toast.LENGTH_SHORT).show();
                    load2FAStatus();
                } else {
                    Toast.makeText(TwoFAManagementActivity.this, 
                            "Failed to enable 2FA", Toast.LENGTH_SHORT).show();
                }
            }
        }.execute(token);
    }

    private void enable2FA() {
        // Включение через setup + verify уже реализовано выше
        setup2FA();
    }

    private void disable2FA() {
        Disable2FADialog dialog = new Disable2FADialog(this, (password) -> {
            confirmDisable2FA(password);
        });
        dialog.show();
    }

    private void confirmDisable2FA(String password) {
        new AsyncTask<String, Void, JSONObject>() {
            @Override
            protected JSONObject doInBackground(String... passwords) {
                try {
                    JSONObject payload = new JSONObject();
                    payload.put("password", passwords[0]);
                    return NetworkUtils.sendPostRequest("/api/2fa/disable", payload, currentToken);
                } catch (Exception e) {
                    return null;
                }
            }

            @Override
            protected void onPostExecute(JSONObject result) {
                if (result != null && result.optBoolean("success")) {
                    Toast.makeText(TwoFAManagementActivity.this, 
                            "2FA disabled successfully", Toast.LENGTH_SHORT).show();
                    load2FAStatus();
                } else {
                    String error = result != null ? result.optString("error", "Failed to disable 2FA") : "Failed to disable 2FA";
                    Toast.makeText(TwoFAManagementActivity.this, error, Toast.LENGTH_SHORT).show();
                    switch2FA.setChecked(true); // Возвращаем переключатель в исходное положение
                }
            }
        }.execute(password);
    }
}
