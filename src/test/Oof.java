
public class Oof {
    short a = 100;

    static int b = 123;

    int nice(int i) {
        return a + i;
    }

    static int niceStatic(int i) {
        return b + i;
    }

    public static void main(String[] args) {
        Oof oof = new Oof();
        int b = oof.nice(2);
    }
}