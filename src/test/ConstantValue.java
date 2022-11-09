//! skip
// skip until reflection works
public class ConstantValue {
    private static final int INT = 500;
    private static final double DOUBLE = 20.123;
    private static final byte BYTE = -23;
    private static final String STRING = "oohlala";

    public static int vmTest() throws IllegalArgumentException, IllegalAccessException, NoSuchFieldException, SecurityException {
        if (INT != 500) return 1;
        if (DOUBLE != 20.123) return 2;
        if (BYTE != -23) return 3;

        // otherwise it just ldc constant
        String s = (String) ConstantValue.class.getField("STRING").get(null);
        if (!s.equals("oohlala")) return 4;
        return 0;
    }

}
