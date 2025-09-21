package org.debianrose.dumb;

import android.content.Context;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ArrayAdapter;
import android.widget.ImageButton;
import android.widget.ProgressBar;
import android.widget.TextView;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.List;
import java.util.Locale;

public class MessageAdapter extends ArrayAdapter<Message> {

    private final Context context;
    private final List<Message> messages;

    public MessageAdapter(Context context, List<Message> messages) {
        super(context, R.layout.message_item, messages);
        this.context = context;
        this.messages = messages;
    }

    @NonNull
    @Override
    public View getView(int position, @Nullable View convertView, @NonNull ViewGroup parent) {
        View view = convertView;
        if (view == null) {
            view = LayoutInflater.from(context).inflate(R.layout.message_item, parent, false);
        }

        Message message = messages.get(position);
        TextView tvSender = view.findViewById(R.id.tvSender);
        TextView tvMessage = view.findViewById(R.id.tvMessage);
        TextView tvTime = view.findViewById(R.id.tvTime);
        ImageButton btnPlayVoice = view.findViewById(R.id.btnPlayVoice);
        TextView tvVoiceDuration = view.findViewById(R.id.tvVoiceDuration);
        ProgressBar voiceProgress = view.findViewById(R.id.voiceProgress);
        View voiceLayout = view.findViewById(R.id.voiceLayout);

        tvSender.setText(message.from);
        tvMessage.setText(message.text);
        tvTime.setText(new SimpleDateFormat("HH:mm", Locale.getDefault())
                .format(new Date(message.timestamp)));

        if (message.voice != null) {
            voiceLayout.setVisibility(View.VISIBLE);
            tvVoiceDuration.setText(formatDuration(message.voice.duration));
            
            if (context instanceof ChatActivity) {
                ChatActivity chatActivity = (ChatActivity) context;
                boolean isPlaying = chatActivity.isVoicePlaying(message.id);
                
                if (isPlaying) {
                    btnPlayVoice.setImageResource(R.drawable.ic_pause);
                    int progress = chatActivity.getVoiceProgress(message.id);
                    voiceProgress.setProgress(progress);
                } else {
                    btnPlayVoice.setImageResource(R.drawable.ic_mic);
                    voiceProgress.setProgress(0);
                }
            }
            
            btnPlayVoice.setOnClickListener(v -> {
                if (context instanceof ChatActivity) {
                    ((ChatActivity) context).toggleVoiceMessage(message);
                }
            });
        } else {
            voiceLayout.setVisibility(View.GONE);
        }

        return view;
    }

    private String formatDuration(int seconds) {
        if (seconds <= 0) return "0:00";
        return String.format(Locale.getDefault(), "%d:%02d", seconds / 60, seconds % 60);
    }
}
