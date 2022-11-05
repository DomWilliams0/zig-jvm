public class LongToInt {

    public static int vmTest() {
        long i = 0x100000007L;
        int one = (int) (i >> 32);
        int seven = (int) i;
        if (one != 1) throw new RuntimeException();
        if (seven != 7) throw new RuntimeException();
        return 0;
    }

}
