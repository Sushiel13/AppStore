package com.appbucket.adshield;

import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.security.AlgorithmParameters;
import java.security.KeyFactory;
import java.security.PublicKey;
import java.security.Signature;
import java.security.spec.ECGenParameterSpec;
import java.security.spec.ECParameterSpec;
import java.security.spec.ECPoint;
import java.security.spec.ECPublicKeySpec;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Checks AdShield Pro unlock codes offline.
 *
 * A code looks like  ADS1Y20271104-<signature>
 *   ADS1      AdShield, code format 1
 *   Y / M     yearly or monthly plan
 *   20271104  Pro works until this date (inclusive)
 *   signature ECDSA P-256 / SHA-256 over "ADS1|<phone id>|<plan>|<yyyymmdd>", made with the owner's
 *             private key on appbucket.in/owner (the same key as House Help Tracker; the "ADS1" prefix
 *             is signed too, so a House Help Tracker code can never unlock AdShield or the other way round).
 * The phone ID is not in the code: it is inside the signature, so a code works on one phone only.
 */
public final class License {

    /** Owner's public key (JWK x, y; base64url). Only the private half can make codes. */
    static final String PUB_X = "nelmSU5LeYlXUs5BppqWp1S5Pk6C3P_ZtRvLfqvkZ4k";
    static final String PUB_Y = "QQWTfq8x1HYObdpBbUXdAiu8eEuOzmtVv8cNo5POaZ4";

    private static final Pattern CODE = Pattern.compile("^ADS1([MY])(\\d{8})-([A-Za-z0-9_-]{80,90})$");

    public static final class Result {
        public final String plan;     // "M" or "Y"
        public final String expires;  // yyyy-MM-dd
        public final String code;

        Result(String plan, String expires, String code) {
            this.plan = plan;
            this.expires = expires;
            this.code = code;
        }
    }

    private License() {
    }

    /** The cleaned-up code if it is genuine for this phone, else null. */
    public static Result verify(String raw, String phoneId) {
        if (raw == null || phoneId == null) return null;
        String code = raw.replaceAll("\\s+", "").trim();
        Matcher m = CODE.matcher(code);
        if (!m.matches()) return null;
        String plan = m.group(1), ymd = m.group(2);
        try {
            byte[] sig = b64u(m.group(3));
            if (sig.length != 64) return null;
            Signature s = Signature.getInstance("SHA256withECDSA");
            s.initVerify(publicKey());
            s.update(("ADS1|" + phoneId + "|" + plan + "|" + ymd).getBytes(StandardCharsets.UTF_8));
            if (!s.verify(rawToDer(sig))) return null;
        } catch (Exception e) {
            return null;
        }
        String exp = ymd.substring(0, 4) + "-" + ymd.substring(4, 6) + "-" + ymd.substring(6);
        return new Result(plan, exp, code);
    }

    private static PublicKey cached;

    private static synchronized PublicKey publicKey() throws Exception {
        if (cached == null) {
            AlgorithmParameters params = AlgorithmParameters.getInstance("EC");
            params.init(new ECGenParameterSpec("secp256r1"));
            ECParameterSpec spec = params.getParameterSpec(ECParameterSpec.class);
            ECPoint w = new ECPoint(new BigInteger(1, b64u(PUB_X)),
                    new BigInteger(1, b64u(PUB_Y)));
            cached = KeyFactory.getInstance("EC").generatePublic(new ECPublicKeySpec(w, spec));
        }
        return cached;
    }

    /** base64url without padding (java.util.Base64 needs Android 8; AdShield supports 7). */
    static byte[] b64u(String s) {
        String a = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
        java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
        int buf = 0, bits = 0;
        for (char c : s.toCharArray()) {
            int v = a.indexOf(c);
            if (v < 0) throw new IllegalArgumentException("bad base64url");
            buf = (buf << 6) | v;
            bits += 6;
            if (bits >= 8) {
                bits -= 8;
                out.write((buf >> bits) & 0xFF);
            }
        }
        return out.toByteArray();
    }

    /** WebCrypto signs as raw r||s (64 bytes); Java verifies DER. */
    static byte[] rawToDer(byte[] raw) {
        byte[] r = derInt(raw, 0), s = derInt(raw, 32);
        int len = 2 + r.length + 2 + s.length;
        byte[] out = new byte[2 + len];
        int i = 0;
        out[i++] = 0x30;
        out[i++] = (byte) len;
        out[i++] = 0x02;
        out[i++] = (byte) r.length;
        System.arraycopy(r, 0, out, i, r.length);
        i += r.length;
        out[i++] = 0x02;
        out[i++] = (byte) s.length;
        System.arraycopy(s, 0, out, i, s.length);
        return out;
    }

    private static byte[] derInt(byte[] raw, int off) {
        int start = off;
        while (start < off + 31 && raw[start] == 0) start++;          // strip leading zeros
        boolean pad = (raw[start] & 0x80) != 0;                       // keep it positive
        byte[] v = new byte[off + 32 - start + (pad ? 1 : 0)];
        System.arraycopy(raw, start, v, pad ? 1 : 0, off + 32 - start);
        return v;
    }
}
