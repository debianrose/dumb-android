package org.debianrose.dumb;

import android.Manifest;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.media.AudioManager;
import android.os.AsyncTask;
import android.os.Bundle;
import android.os.Handler;
import android.view.View;
import android.widget.Button;
import android.widget.TextView;
import android.widget.Toast;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.content.ContextCompat;
import org.json.JSONObject;
import org.webrtc.AudioTrack;
import org.webrtc.DataChannel;
import org.webrtc.IceCandidate;
import org.webrtc.MediaConstraints;
import org.webrtc.MediaStream;
import org.webrtc.PeerConnection;
import org.webrtc.PeerConnectionFactory;
import org.webrtc.RtpReceiver;
import org.webrtc.SessionDescription;
import java.util.ArrayList;
import java.util.List;

public class VoiceCallActivity extends AppCompatActivity implements PeerConnection.Observer {

    private TextView tvCallStatus;
    private Button btnEndCall, btnToggleAudio, btnAnswer;
    private PeerConnectionFactory peerConnectionFactory;
    private PeerConnection peerConnection;
    private AudioTrack localAudioTrack;
    private String currentToken;
    private String currentUser;
    private String targetUser;
    private String currentChannelId;
    private boolean isAudioMuted = false;
    private boolean isIncomingCall = false;
    private List<IceCandidate> iceCandidates = new ArrayList<>();
    private Handler handler = new Handler();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_voice_call);

        currentToken = getIntent().getStringExtra("token");
        currentUser = getIntent().getStringExtra("username");
        targetUser = getIntent().getStringExtra("targetUser");
        currentChannelId = getIntent().getStringExtra("channelId");
        isIncomingCall = getIntent().getBooleanExtra("isIncoming", false);

        initViews();
        checkPermissions();
        
        initializeWebRTC();
        
        if (isIncomingCall) {
            handleIncomingCall();
        } else {
            createPeerConnection();
            createLocalMediaStream();
            initCall();
        }
    }

    private void initViews() {
        tvCallStatus = findViewById(R.id.tvCallStatus);
        btnEndCall = findViewById(R.id.btnEndCall);
        btnToggleAudio = findViewById(R.id.btnToggleAudio);
        btnAnswer = findViewById(R.id.btnAnswer);

        btnEndCall.setOnClickListener(v -> endCall());
        btnToggleAudio.setOnClickListener(v -> toggleAudio());

        if (isIncomingCall) {
            tvCallStatus.setText("Incoming call from " + targetUser);
            btnAnswer.setVisibility(View.VISIBLE);
            btnAnswer.setOnClickListener(v -> answerCall());
        } else {
            tvCallStatus.setText("Calling " + targetUser + "...");
        }
    }

    private void handleIncomingCall() {
        tvCallStatus.setText("Incoming call from " + targetUser);
        btnAnswer.setVisibility(View.VISIBLE);
    }

    private void checkPermissions() {
        String[] permissions = {Manifest.permission.RECORD_AUDIO};
        List<String> permissionsToRequest = new ArrayList<>();
        
        for (String permission : permissions) {
            if (ContextCompat.checkSelfPermission(this, permission) != PackageManager.PERMISSION_GRANTED) {
                permissionsToRequest.add(permission);
            }
        }

        if (!permissionsToRequest.isEmpty()) {
            requestPermissions(permissionsToRequest.toArray(new String[0]), 101);
        }
    }

    private void initializeWebRTC() {
        PeerConnectionFactory.InitializationOptions initializationOptions =
                PeerConnectionFactory.InitializationOptions.builder(this)
                        .createInitializationOptions();
        PeerConnectionFactory.initialize(initializationOptions);

        PeerConnectionFactory.Options options = new PeerConnectionFactory.Options();
        peerConnectionFactory = PeerConnectionFactory.builder()
                .setOptions(options)
                .createPeerConnectionFactory();
    }

    private void createPeerConnection() {
        List<PeerConnection.IceServer> iceServers = new ArrayList<>();
        iceServers.add(PeerConnection.IceServer.builder("stun:stun.l.google.com:19302").createIceServer());
        iceServers.add(PeerConnection.IceServer.builder("stun:stun1.l.google.com:19302").createIceServer());

        PeerConnection.RTCConfiguration rtcConfig = new PeerConnection.RTCConfiguration(iceServers);
        peerConnection = peerConnectionFactory.createPeerConnection(rtcConfig, this);
    }

    private void createLocalMediaStream() {
        MediaStream localStream = peerConnectionFactory.createLocalMediaStream("local_stream");

        AudioManager audioManager = (AudioManager) getSystemService(AUDIO_SERVICE);
        audioManager.setMode(AudioManager.MODE_IN_COMMUNICATION);
        audioManager.setSpeakerphoneOn(true);

        MediaConstraints audioConstraints = new MediaConstraints();
        localAudioTrack = peerConnectionFactory.createAudioTrack("audio_track", 
                peerConnectionFactory.createAudioSource(audioConstraints));
        localStream.addTrack(localAudioTrack);

        peerConnection.addStream(localStream);
    }

    private void initCall() {
        createOffer();
    }

    private void createOffer() {
        MediaConstraints constraints = new MediaConstraints();
        constraints.mandatory.add(new MediaConstraints.KeyValuePair("OfferToReceiveAudio", "true"));

        peerConnection.createOffer(new SimpleSdpObserver() {
            @Override
            public void onCreateSuccess(SessionDescription sessionDescription) {
                peerConnection.setLocalDescription(new SimpleSdpObserver() {
                    @Override
                    public void onSetSuccess() {
                        sendWebRTCOffer(sessionDescription);
                    }
                }, sessionDescription);
            }
        }, constraints);
    }

    private void sendWebRTCOffer(SessionDescription offer) {
        new AsyncTask<Void, Void, JSONObject>() {
            @Override
            protected JSONObject doInBackground(Void... voids) {
                try {
                    JSONObject payload = new JSONObject();
                    payload.put("toUser", targetUser);
                    payload.put("offer", offer.description);
                    payload.put("channel", currentChannelId);
                    return NetworkUtils.sendPostRequest("/api/webrtc/offer", payload, currentToken);
                } catch (Exception e) {
                    return null;
                }
            }

            @Override
            protected void onPostExecute(JSONObject result) {
                if (result == null || !result.optBoolean("success")) {
                    Toast.makeText(VoiceCallActivity.this, "Failed to send offer", Toast.LENGTH_SHORT).show();
                    finish();
                }
            }
        }.execute();
    }

    private void answerCall() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO}, 201);
            return;
        }
        
        createLocalMediaStream();
        getWebRTCOffer();
    }

    private void getWebRTCOffer() {
        new AsyncTask<Void, Void, JSONObject>() {
            @Override
            protected JSONObject doInBackground(Void... voids) {
                try {
                    return NetworkUtils.sendGetRequest("/api/webrtc/offer?fromUser=" + targetUser, currentToken);
                } catch (Exception e) {
                    return null;
                }
            }

            @Override
            protected void onPostExecute(JSONObject result) {
                if (result != null && result.optBoolean("success")) {
                    String offerSdp = result.optString("offer");
                    
                    SessionDescription offer = new SessionDescription(SessionDescription.Type.OFFER, offerSdp);
                    
                    peerConnection.setRemoteDescription(new SimpleSdpObserver() {
                        @Override
                        public void onSetSuccess() {
                            createAnswer();
                        }
                    }, offer);
                    
                } else {
                    Toast.makeText(VoiceCallActivity.this, "Failed to get offer", Toast.LENGTH_SHORT).show();
                    finish();
                }
            }
        }.execute();
    }

    private void createAnswer() {
        MediaConstraints constraints = new MediaConstraints();
        constraints.mandatory.add(new MediaConstraints.KeyValuePair("OfferToReceiveAudio", "true"));

        peerConnection.createAnswer(new SimpleSdpObserver() {
            @Override
            public void onCreateSuccess(SessionDescription sessionDescription) {
                peerConnection.setLocalDescription(new SimpleSdpObserver() {
                    @Override
                    public void onSetSuccess() {
                        sendWebRTCAnswer(sessionDescription);
                        tvCallStatus.setText("Connected to " + targetUser);
                        btnAnswer.setVisibility(View.GONE);
                    }
                }, sessionDescription);
            }
        }, constraints);
    }

    private void sendWebRTCAnswer(SessionDescription answer) {
        new AsyncTask<Void, Void, JSONObject>() {
            @Override
            protected JSONObject doInBackground(Void... voids) {
                try {
                    JSONObject payload = new JSONObject();
                    payload.put("toUser", targetUser);
                    payload.put("answer", answer.description);
                    return NetworkUtils.sendPostRequest("/api/webrtc/answer", payload, currentToken);
                } catch (Exception e) {
                    return null;
                }
            }

            @Override
            protected void onPostExecute(JSONObject result) {
                if (result == null || !result.optBoolean("success")) {
                    Toast.makeText(VoiceCallActivity.this, "Failed to send answer", Toast.LENGTH_SHORT).show();
                }
            }
        }.execute();
    }

    @Override
    public void onIceCandidate(IceCandidate iceCandidate) {
        iceCandidates.add(iceCandidate);
        sendIceCandidate(iceCandidate);
    }

    @Override
    public void onIceCandidatesRemoved(IceCandidate[] iceCandidates) {}

    @Override
    public void onIceConnectionReceivingChange(boolean receiving) {}

    @Override
    public void onAddStream(MediaStream mediaStream) {
        runOnUiThread(() -> {
            tvCallStatus.setText("Connected to " + targetUser);
        });
    }

    @Override
    public void onRemoveStream(MediaStream mediaStream) {
        runOnUiThread(() -> {
            tvCallStatus.setText("Call ended");
        });
    }

    @Override
    public void onDataChannel(DataChannel dataChannel) {}

    @Override
    public void onSignalingChange(PeerConnection.SignalingState signalingState) {}

    @Override
    public void onIceConnectionChange(PeerConnection.IceConnectionState iceConnectionState) {
        runOnUiThread(() -> {
            if (iceConnectionState == PeerConnection.IceConnectionState.DISCONNECTED ||
                iceConnectionState == PeerConnection.IceConnectionState.FAILED) {
                tvCallStatus.setText("Call disconnected");
                handler.postDelayed(() -> finish(), 2000);
            }
        });
    }

    @Override
    public void onIceGatheringChange(PeerConnection.IceGatheringState iceGatheringState) {}

    @Override
    public void onRenegotiationNeeded() {}

    @Override
    public void onAddTrack(RtpReceiver rtpReceiver, MediaStream[] mediaStreams) {}

    private void sendIceCandidate(IceCandidate iceCandidate) {
        new AsyncTask<Void, Void, JSONObject>() {
            @Override
            protected JSONObject doInBackground(Void... voids) {
                try {
                    JSONObject payload = new JSONObject();
                    payload.put("toUser", targetUser);
                    payload.put("candidate", iceCandidate.sdp);
                    payload.put("sdpMid", iceCandidate.sdpMid);
                    payload.put("sdpMLineIndex", iceCandidate.sdpMLineIndex);
                    return NetworkUtils.sendPostRequest("/api/webrtc/ice-candidate", payload, currentToken);
                } catch (Exception e) {
                    return null;
                }
            }
        }.execute();
    }

    private void toggleAudio() {
        isAudioMuted = !isAudioMuted;
        if (localAudioTrack != null) {
            localAudioTrack.setEnabled(!isAudioMuted);
        }
        btnToggleAudio.setText(isAudioMuted ? "Unmute" : "Mute");
    }

    private void endCall() {
        new AsyncTask<Void, Void, JSONObject>() {
            @Override
            protected JSONObject doInBackground(Void... voids) {
                try {
                    JSONObject payload = new JSONObject();
                    payload.put("targetUser", targetUser);
                    return NetworkUtils.sendPostRequest("/api/webrtc/end-call", payload, currentToken);
                } catch (Exception e) {
                    return null;
                }
            }

            @Override
            protected void onPostExecute(JSONObject result) {
                finish();
            }
        }.execute();
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (peerConnection != null) {
            peerConnection.close();
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == 101) {
            if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                if (!isIncomingCall) {
                    createPeerConnection();
                    createLocalMediaStream();
                    initCall();
                }
            }
        } else if (requestCode == 201) {
            if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                answerCall();
            }
        }
    }

    private abstract class SimpleSdpObserver implements org.webrtc.SdpObserver {
        @Override public void onCreateSuccess(SessionDescription sessionDescription) {}
        @Override public void onSetSuccess() {}
        @Override public void onCreateFailure(String s) {}
        @Override public void onSetFailure(String s) {}
    }
}
