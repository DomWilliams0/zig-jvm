
public class SimpleInstance {
    short a = 100;

    int nice(int i) {
        return a + i;
    }

    public static int vmTest() {
        SimpleInstance x = new SimpleInstance();
        return x.nice(-100);
    }
}
