// no overriding
public class SuperField {
    static int nonsense = 0;

    int a = 100;
    static int b = 5;

    static class Inner extends SuperField {
        int c = 50;
        static int d = 6;
    }

    public static int vmTest() {
        Inner x = new Inner();
        return (161 - x.a - x.b - x.c - x.d);
    }

}
