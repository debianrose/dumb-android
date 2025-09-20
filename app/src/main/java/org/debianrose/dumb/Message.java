package org.debianrose.dumb;

public class Message {
    String id;
    String from;
    String text;
    long timestamp;
    String channel;
    VoiceAttachment voice;

    Message(String id, String from, String text, long timestamp, String channel) {
        this.id = id;
        this.from = from;
        this.text = text;
        this.timestamp = timestamp;
        this.channel = channel;
    }

    Message(String id, String from, String text, long timestamp, String channel, VoiceAttachment voice) {
        this.id = id;
        this.from = from;
        this.text = text;
        this.timestamp = timestamp;
        this.channel = channel;
        this.voice = voice;
    }

    public static class VoiceAttachment {
        String filename;
        int duration;
        String downloadUrl;

        public VoiceAttachment(String filename, int duration, String downloadUrl) {
            this.filename = filename;
            this.duration = duration;
            this.downloadUrl = downloadUrl;
        }
    }
}
