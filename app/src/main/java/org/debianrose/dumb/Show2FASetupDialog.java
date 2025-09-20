package org.debianrose.dumb;

import android.app.Dialog;
import android.content.Context;
import android.graphics.Bitmap;
import android.os.Bundle;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.NonNull;

import android.util.Base64;

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

        // Загрузка QR-кода (упрощенная версия)
        new LoadQrCodeTask(ivQrCode).execute(qrCodeUrl);

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

    private static class LoadQrCodeTask extends AsyncTask<String, Void, Bitmap> {
        private final ImageView imageView;

        LoadQrCodeTask(ImageView imageView) {
            this.imageView = imageView;
        }

        @Override
        protected Bitmap doInBackground(String... urls) {
            try {
                // Упрощенная реализация - в реальном приложении используйте библиотеку для загрузки изображений
                String base64Data = urls[0].split(",")[1];
                byte[] decodedBytes = Base64.decode(base64Data, Base64.DEFAULT);
                // Конвертация byte[] в Bitmap (упрощенно)
                // В реальном приложении используйте BitmapFactory.decodeByteArray()
                return null; // Заглушка
            } catch (Exception e) {
                return null;
            }
        }

        @Override
        protected void onPostExecute(Bitmap bitmap) {
            if (bitmap != null) {
                imageView.setImageBitmap(bitmap);
            }
        }
    }

    public interface TwoFACallback {
        void onTokenEntered(String token);
    }
}
