package org.debianrose.dumb;

import android.app.Dialog;
import android.content.Context;
import android.os.Bundle;
import android.widget.Button;
import android.widget.EditText;
import android.widget.Toast;

import androidx.annotation.NonNull;

public class TwoFADialog extends Dialog {

    private final String sessionId;
    private final String username;
    private final TwoFACallback callback;

    public TwoFADialog(@NonNull Context context, String sessionId, String username, TwoFACallback callback) {
        super(context);
        this.sessionId = sessionId;
        this.username = username;
        this.callback = callback;
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.dialog_2fa);

        EditText etToken = findViewById(R.id.etToken);
        Button btnSubmit = findViewById(R.id.btnSubmit);

        btnSubmit.setOnClickListener(v -> {
            String token = etToken.getText().toString().trim();
            if (token.length() == 6) {
                callback.onTokenEntered(token);
                dismiss();
            } else {
                Toast.makeText(getContext(), "Please enter a valid 6-digit code", Toast.LENGTH_SHORT).show();
            }
        });
    }

    public interface TwoFACallback {
        void onTokenEntered(String token);
    }
}
