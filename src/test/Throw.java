
public class Throw {

    static void hehe() {
        throw new RuntimeException("oof");

    }

    public static int vmTest() {
        try {
            hehe();
            return 1;
            // throw null;

        } catch (RuntimeException exc) {
            return 0;
        }
    }
}