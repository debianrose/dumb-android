package org.debianrose.dumb;

import android.media.MediaRecorder;
import android.os.Environment;
import android.util.Log;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;

public class VoiceMessageUtils {

    private static final String TAG = "VoiceMessageUtils";

    public static File recordVoiceMessage(int durationSeconds) {
        try {
            File wavFile = new File(Environment.getExternalStorageDirectory(), "voice_message.wav");
            
            File tempFile = new File(Environment.getExternalStorageDirectory(), "temp_audio.3gp");
            
            MediaRecorder recorder = new MediaRecorder();
            recorder.setAudioSource(MediaRecorder.AudioSource.MIC);
            recorder.setOutputFormat(MediaRecorder.OutputFormat.THREE_GPP);
            recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AMR_NB);
            recorder.setOutputFile(tempFile.getAbsolutePath());
            recorder.setAudioSamplingRate(44100);
            recorder.setAudioEncodingBitRate(128000);
            recorder.setAudioChannels(1);

            recorder.prepare();
            recorder.start();
            Thread.sleep(durationSeconds * 1000);
            recorder.stop();
            recorder.release();

            convertToWav(tempFile, wavFile, 44100, 1);
            tempFile.delete();

            return wavFile;

        } catch (Exception e) {
            Log.e(TAG, "Voice recording failed", e);
            return null;
        }
    }

    private static void convertToWav(File inputFile, File wavFile, int sampleRate, int channels) throws IOException {
        FileInputStream fis = new FileInputStream(inputFile);
        FileOutputStream fos = new FileOutputStream(wavFile);

        // WAV header
        long totalAudioLen = fis.getChannel().size();
        long totalDataLen = totalAudioLen + 36;
        long byteRate = sampleRate * channels * 16 / 8;

        byte[] header = new byte[44];
        // RIFF header
        header[0] = 'R'; header[1] = 'I'; header[2] = 'F'; header[3] = 'F';
        header[4] = (byte) (totalDataLen & 0xff);
        header[5] = (byte) ((totalDataLen >> 8) & 0xff);
        header[6] = (byte) ((totalDataLen >> 16) & 0xff);
        header[7] = (byte) ((totalDataLen >> 24) & 0xff);
        // WAVE header
        header[8] = 'W'; header[9] = 'A'; header[10] = 'V'; header[11] = 'E';
        // fmt chunk
        header[12] = 'f'; header[13] = 'm'; header[14] = 't'; header[15] = ' ';
        header[16] = 16; header[17] = 0; header[18] = 0; header[19] = 0;
        header[20] = 1; header[21] = 0; // PCM format
        header[22] = (byte) channels;
        header[23] = 0;
        header[24] = (byte) (sampleRate & 0xff);
        header[25] = (byte) ((sampleRate >> 8) & 0xff);
        header[26] = (byte) ((sampleRate >> 16) & 0xff);
        header[27] = (byte) ((sampleRate >> 24) & 0xff);
        header[28] = (byte) (byteRate & 0xff);
        header[29] = (byte) ((byteRate >> 8) & 0xff);
        header[30] = (byte) ((byteRate >> 16) & 0xff);
        header[31] = (byte) ((byteRate >> 24) & 0xff);
        header[32] = (byte) (channels * 16 / 8); // block align
        header[33] = 0;
        header[34] = 16; // bits per sample
        header[35] = 0;
        header[36] = 'd'; header[37] = 'a'; header[38] = 't'; header[39] = 'a';
        header[40] = (byte) (totalAudioLen & 0xff);
        header[41] = (byte) ((totalAudioLen >> 8) & 0xff);
        header[42] = (byte) ((totalAudioLen >> 16) & 0xff);
        header[43] = (byte) ((totalAudioLen >> 24) & 0xff);

        fos.write(header);

        byte[] buffer = new byte[1024];
        int bytesRead;
        while ((bytesRead = fis.read(buffer)) != -1) {
            fos.write(buffer, 0, bytesRead);
        }

        fis.close();
        fos.close();
    }

}
