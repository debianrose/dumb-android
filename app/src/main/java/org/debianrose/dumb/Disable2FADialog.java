package org.debianrose.dumb;

import android.app.Dialog;
import android.content.Context;
import android.os.Bundle;
import android.widget.Button;
import android.widget.EditText;
import android.widget.Toast;

import androidx.annotation.NonNull;

public class Disable2FADialog extends Dialog {

    private final PasswordCallback callback;

    public Disable2FADialog(@NonNull Context context, PasswordCallback callback) {
        super(context);
        this.callback = callback;
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.dialog_disable_2fa);

        EditText etPassword = findViewById(R.id.etPassword);
        Button btnConfirm = findViewById(R.id.btnConfirm);
        Button btnCancel = findViewById(R.id.btnCancel);

        btnConfirm.setOnClickListener(v -> {
            String password = etPassword.getText().toString().trim();
            if (password.length() >= 4) {
                callback.onPasswordEntered(password);
                dismiss();
            } else {
                Toast.makeText(getContext(), "Please enter your password", Toast.LENGTH_SHORT).show();
            }
        });

        btnCancel.setOnClickListener(v -> dismiss());
    }

    public interface PasswordCallback {
        void onPasswordEntered(String password);
    }
}
