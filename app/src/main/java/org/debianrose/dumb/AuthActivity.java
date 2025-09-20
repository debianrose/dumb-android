package org.debianrose.dumb;

import android.content.Intent;
import android.os.AsyncTask;
import android.os.Bundle;
import android.text.TextUtils;
import android.widget.Button;
import android.widget.EditText;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;

import org.json.JSONObject;

public class AuthActivity extends AppCompatActivity {

    private EditText etUsername, etPassword;
    private Button btnLogin, btnRegister;
    private String currentToken = null;
    private String currentUser = null;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_auth);

        etUsername = findViewById(R.id.etUsername);
        etPassword = findViewById(R.id.etPassword);
        btnLogin = findViewById(R.id.btnLogin);
        btnRegister = findViewById(R.id.btnRegister);

        btnLogin.setOnClickListener(v -> login());
        btnRegister.setOnClickListener(v -> register());
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

                    return NetworkUtils.sendPostRequest("/api/login", payload, null);
                } catch (Exception e) {
                    return null;
                }
            }

            @Override
            protected void onPostExecute(JSONObject result) {
                if (result != null && result.optBoolean("success")) {
                    currentToken = result.optString("token");
                    currentUser = username;
                    
                    if (result.optBoolean("requires2FA", false)) {
                        handle2FALogin(result.optString("sessionId"), username);
                    } else {
                        proceedToChannelSelection();
                    }
                } else {
                    String error = result != null ? result.optString("error", "Login failed") : "Login failed";
                    Toast.makeText(AuthActivity.this, error, Toast.LENGTH_SHORT).show();
                }
            }
        }.execute();
    }

    private void handle2FALogin(String sessionId, String username) {
        TwoFADialog dialog = new TwoFADialog(this, sessionId, username, 
            (token) -> verify2FALogin(sessionId, username, token));
        dialog.show();
    }

    private void verify2FALogin(String sessionId, String username, String twoFactorToken) {
        new AsyncTask<Void, Void, JSONObject>() {
            @Override
            protected JSONObject doInBackground(Void... voids) {
                try {
                    JSONObject payload = new JSONObject();
                    payload.put("username", username);
                    payload.put("sessionId", sessionId);
                    payload.put("twoFactorToken", twoFactorToken);

                    return NetworkUtils.sendPostRequest("/api/2fa/verify-login", payload, null);
                } catch (Exception e) {
                    return null;
                }
            }

            @Override
            protected void onPostExecute(JSONObject result) {
                if (result != null && result.optBoolean("success")) {
                    currentToken = result.optString("token");
                    currentUser = username;
                    proceedToChannelSelection();
                } else {
                    String error = result != null ? result.optString("error", "2FA verification failed") : "2FA verification failed";
                    Toast.makeText(AuthActivity.this, error, Toast.LENGTH_SHORT).show();
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

                    return NetworkUtils.sendPostRequest("/api/register", payload, null);
                } catch (Exception e) {
                    return null;
                }
            }

            @Override
            protected void onPostExecute(JSONObject result) {
                if (result != null && result.optBoolean("success")) {
                    Toast.makeText(AuthActivity.this, "Registration successful", Toast.LENGTH_SHORT).show();
                } else {
                    String error = result != null ? result.optString("error", "Registration failed") : "Registration failed";
                    Toast.makeText(AuthActivity.this, error, Toast.LENGTH_SHORT).show();
                }
            }
        }.execute();
    }

    private void proceedToChannelSelection() {
        Intent intent = new Intent(this, ChannelSelectionActivity.class);
        intent.putExtra("token", currentToken);
        intent.putExtra("username", currentUser);
        startActivity(intent);
        finish();
    }
}
