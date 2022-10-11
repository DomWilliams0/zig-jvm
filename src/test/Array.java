
public class Array {

    int value = 2;

    public static int vmTest() {
        int[] arr = new int[]{4, 5, 10, 20}; // sum = 39
        short[] arr2 = new short[]{-20, -4, -5, -11}; // sum = -40
        Array[] arr3 = new Array[]{new Array(), new Array()}; // sum = 4
        byte[] arr4 = new byte[]{-2, 10}; // sum = 8
        // long[] arr5 = new long[]{500000, -500008}; // sum = -8

        int sum = -3;
        for (int x : arr) sum += x;
        for (short x : arr2) sum += x;
        for (Array x : arr3) sum += x.value;
        for (byte x : arr4) sum += x;
        // for (long x : arr5) sum += x;
        sum -= 8; // until long array works

        return sum;

    }
}