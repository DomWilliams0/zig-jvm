
public class SimpleStatics {

    static int ooh = 102;

    static int nice(int i) {
        return ooh + i;
    }

    public static int vmTest() {
        SimpleStatics.ooh -= 2;
        return SimpleStatics.nice(-100);
    }
}