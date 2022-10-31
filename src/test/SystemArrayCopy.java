public class SystemArrayCopy {

    static void copyInts() {
        int[] src = new int[] { 0, 1, 2, 3, 4, 5, 6 };
        int[] dst = new int[10];

        System.arraycopy(src, 2, dst, 4, 4);
        if (!(dst[0] == 0 && dst[1] == 0 && dst[2] == 0 && dst[3] == 0 && dst[4] == 2 && dst[5] == 3 && dst[6] == 4
                && dst[7] == 5 && dst[8] == 0 && dst[9] == 0))
            throw new RuntimeException("copy ints");
    }

    static void copyStrings() {
        String[] src = new String[]{"one", "two", "three", "four", null ,"six"};
        Object[] dst = new Object[3];

        System.arraycopy(src, 3, dst, 0, 3);
        if (!(dst[0].equals("four") && dst[1] == null && dst[2].equals("six")))
            throw new RuntimeException("copy strings");
    }

    public static int vmTest() {
        copyInts();
        copyStrings();

        return 0;
    }
}