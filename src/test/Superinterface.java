public class Superinterface {
    static interface Iface {}
    static class A implements Iface {}
    static class B extends A {}

    public static int vmTest() {
        B b = new B();
        if (!(b instanceof Iface)) return 1;
        return 0;
    }

}
