package org.debianrose.dumb;

import android.app.Dialog;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.AsyncTask;
import android.os.Bundle;
import android.util.Base64;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.NonNull;

import java.io.ByteArrayInputStream;
import java.io.InputStream;

public class Show2FASetupDialog extends Dialog {

    private final String secret;
    private final String qrCodeUrl;
    private final TwoFACallback callback;

    public Show2FASetupDialog(@NonNull Context context, String secret, String qrCodeUrl, TwoFACallback callback) {
        super(context);
        this.secret = secret;
        this.qrCodeUrl = qrCodeUrl;
        this.callback = callback;
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.dialog_2fa_setup);

        TextView tvSecret = findViewById(R.id.tvSecret);
        ImageView ivQrCode = findViewById(R.id.ivQrCode);
        EditText etToken = findViewById(R.id.etToken);
        Button btnVerify = findViewById(R.id.btnVerify);

        tvSecret.setText("Secret: " + secret);

        // Загрузка QR-кода
        loadQrCode(ivQrCode, qrCodeUrl);

        btnVerify.setOnClickListener(v -> {
            String token = etToken.getText().toString().trim();
            if (token.length() == 6) {
                callback.onTokenEntered(token);
                dismiss();
            } else {
                Toast.makeText(getContext(), "Please enter a valid 6-digit code", Toast.LENGTH_SHORT).show();
            }
        });
    }

    private void loadQrCode(ImageView imageView, String qrCodeUrl) {
        new AsyncTask<String, Void, Bitmap>() {
            @Override
            protected Bitmap doInBackground(String... urls) {
                try {
                    if (urls[0].startsWith("data:image")) {
                        // Обработка base64 данных
                        String base64Data = urls[0].split(",")[1];
                        byte[] decodedBytes = Base64.decode(base64Data, Base64.DEFAULT);
                        return BitmapFactory.decodeByteArray(decodedBytes, 0, decodedBytes.length);
                    } else {
                        // Для URL - здесь можно добавить загрузку по сети
                        // Но пока просто возвращаем null для URL
                        return null;
                    }
                } catch (Exception e) {
                    return null;
                }
            }

            @Override
            protected void onPostExecute(Bitmap bitmap) {
                if (bitmap != null) {
                    imageView.setImageBitmap(bitmap);
                } else {
                    // Если не удалось загрузить QR-код, показываем только секрет
                    Toast.makeText(getContext(), "QR code not available", Toast.LENGTH_SHORT).show();
                }
            }
        }.execute(qrCodeUrl);
    }

    public interface TwoFACallback {
        void onTokenEntered(String token);
    }
}
