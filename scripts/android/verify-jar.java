import java.io.File;
import java.io.OutputStream;
import java.security.MessageDigest;
import java.security.cert.X509Certificate;
import java.util.HashSet;
import java.util.HexFormat;
import java.util.Locale;
import java.util.jar.JarFile;

/** Verify every payload entry, rather than relying on jarsigner's summary text. */
class VerifyJar {
    public static void main(String[] args) {
        try {
            if (args.length != 2 || !args[1].matches("[0-9A-Fa-f]{64}")) {
                throw new IllegalArgumentException("Usage: verify-jar.java <jar> <certificate-sha256>");
            }
            var names = new HashSet<String>();
            int payloadCount = 0;
            try (var jar = new JarFile(new File(args[0]), true)) {
                var entries = jar.entries();
                while (entries.hasMoreElements()) {
                    var entry = entries.nextElement();
                    var name = entry.getName();
                    if (!names.add(name)) throw new SecurityException("Duplicate JAR entry: " + name);
                    if (entry.isDirectory()) continue;
                    // Reading to EOF triggers the JDK's digest/signature verification.
                    try (var input = jar.getInputStream(entry)) {
                        input.transferTo(OutputStream.nullOutputStream());
                    }
                    var upper = name.toUpperCase(Locale.ROOT);
                    if (upper.equals("META-INF/MANIFEST.MF") ||
                        upper.matches("META-INF/[^/]+\\.(SF|RSA|DSA|EC)") ||
                        upper.matches("META-INF/SIG-[^/]+")) continue;
                    var signers = entry.getCodeSigners();
                    if (signers == null || signers.length != 1) {
                        throw new SecurityException("Payload must have exactly one signer: " + name);
                    }
                    var certificate = (X509Certificate) signers[0].getSignerCertPath().getCertificates().get(0);
                    certificate.checkValidity();
                    var digest = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(certificate.getEncoded()));
                    if (!digest.equalsIgnoreCase(args[1])) {
                        throw new SecurityException("Unexpected payload signer: " + name);
                    }
                    payloadCount++;
                }
            }
            if (payloadCount == 0) throw new SecurityException("JAR contains no signed payload entries.");
        } catch (Exception error) {
            System.err.println(error.getMessage());
            System.exit(1);
        }
    }
}
