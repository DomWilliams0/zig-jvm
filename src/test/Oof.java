
public interface Oof {
    static int returnSecond(int i, int b) {
        return b;
    }

    static class Impl implements Oof {

        int a = 100;

        static int b = 123;

        int nice(int i) {
            return a + i;
        }

        static int niceStatic(int i) {
            return b + i;
        }
    }

    public static void main(String[] args) {
        // Oof oof = new Oof();
        int x = Oof.returnSecond(20, 100);
    }

}