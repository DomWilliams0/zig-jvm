import java.io.IOException;
import java.io.FileNotFoundException;

public class Throw {

    // should return 7
    static int finally_() {
        int i = 5;

        try {
            String s = null;
            boolean nah = s.equals("nah");
            return i;

        } catch (NullPointerException e) {
            i = 6;
        } finally {
            i = 7;
        }

        return i;

    }

    static void throwing() {
        throw new RuntimeException("catch me");
    }

    static void callsThrowing() {
        throwing();
    }

    static void throwingCls() throws ClassNotFoundException {
        // TODO Class.forName("oof");
    }

    public static int vmTest() {
        try {
            throw new FileNotFoundException("oof");
        } catch (FileNotFoundException ex) {
            // exact match
        } catch (RuntimeException ex) {
            return 1;
        }

        try {
            throw new FileNotFoundException("oof");
        } catch (NullPointerException ex) {
            return 2; // no
        } catch (IOException ex) {
            // subclass
        }

        if (finally_() != 7)
            return 3;

        try {
            callsThrowing();
        } catch (RuntimeException e) {
            // bubbles properly
        }

        // thrown by native code
        try {
            throwingCls();
        } catch (ClassNotFoundException e) {
            // nice
        }

        return 0;
    }
}
