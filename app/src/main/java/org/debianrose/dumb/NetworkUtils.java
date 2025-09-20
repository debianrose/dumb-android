package org.debianrose.dumb;

import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;

public class NetworkUtils {

    private static final String SERVER_URL = "http://95.81.122.186:3000";

    public static JSONObject sendPostRequest(String endpoint, JSONObject payload, String token) throws Exception {
        HttpURLConnection conn = null;
        try {
            URL url = new URL(SERVER_URL + endpoint);
            conn = (HttpURLConnection) url.openConnection();
            conn.setRequestMethod("POST");
            conn.setRequestProperty("Content-Type", "application/json");
            conn.setRequestProperty("Accept", "application/json");
            conn.setConnectTimeout(10000);
            conn.setReadTimeout(10000);
            
            if (token != null) {
                conn.setRequestProperty("Authorization", "Bearer " + token);
            }
            
            conn.setDoOutput(true);
            try (OutputStream os = conn.getOutputStream()) {
                byte[] input = payload.toString().getBytes(StandardCharsets.UTF_8);
                os.write(input, 0, input.length);
            }

            int responseCode = conn.getResponseCode();
            BufferedReader reader;
            if (responseCode >= 200 && responseCode < 300) {
                reader = new BufferedReader(new InputStreamReader(conn.getInputStream()));
            } else {
                reader = new BufferedReader(new InputStreamReader(conn.getErrorStream()));
            }
            
            StringBuilder response = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                response.append(line);
            }
            
            JSONObject result = new JSONObject(response.toString());
            
            if (responseCode >= 200 && responseCode < 300) {
                return result;
            } else {
                throw new Exception("HTTP " + responseCode + ": " + result.optString("error", "Unknown error"));
            }
        } finally {
            if (conn != null) conn.disconnect();
        }
    }

    public static JSONObject sendGetRequest(String endpoint, String token) throws Exception {
        HttpURLConnection conn = null;
        try {
            URL url = new URL(SERVER_URL + endpoint);
            conn = (HttpURLConnection) url.openConnection();
            conn.setRequestMethod("GET");
            conn.setConnectTimeout(10000);
            conn.setReadTimeout(10000);
            if (token != null) {
                conn.setRequestProperty("Authorization", "Bearer " + token);
            }

            int responseCode = conn.getResponseCode();
            BufferedReader reader;
            if (responseCode >= 200 && responseCode < 300) {
                reader = new BufferedReader(new InputStreamReader(conn.getInputStream()));
            } else {
                reader = new BufferedReader(new InputStreamReader(conn.getErrorStream()));
            }
            
            StringBuilder response = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                response.append(line);
            }
            
            JSONObject result = new JSONObject(response.toString());
            
            if (responseCode >= 200 && responseCode < 300) {
                return result;
            } else {
                throw new Exception("HTTP " + responseCode + ": " + result.optString("error", "Unknown error"));
            }
        } finally {
            if (conn != null) conn.disconnect();
        }
    }
}
