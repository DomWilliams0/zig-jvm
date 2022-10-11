
public class Array {

    int value = 2;

    public static int vmTest() {
        int[] arr = new int[]{4, 5, 10, 20}; // sum = 39
        short[] arr2 = new short[]{-20, -4, -5, -11}; // sum = -40
        Array[] arr3 = new Array[]{new Array(), new Array()}; // sum = 4

        int sum = -3;
        for (int x : arr) sum += x;
        for (short x : arr2) sum += x;
        for (Array x : arr3) sum += x.value;

        return sum;

    }
}