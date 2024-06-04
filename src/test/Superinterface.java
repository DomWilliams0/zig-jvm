public class Superinterface {
    static interface Iface {
        int func();
    }

    static interface Iface2 {
        int func2();
    }

    static interface Iface3 extends Iface, Iface2 {
    }

    static class A implements Iface {
        public int func() {
            return 5;
        }
    }

    static class B extends A {
    }

    abstract static class C implements Iface3 {
        public int func2() {return 0;}

        int usesInterface() {
            return func();
        }
    }

    static class D extends C {
        public int func() {
            return 101;
        }
    }

    public static int vmTest() {
        B b = new B();
        if (!(b instanceof Iface))
            return 1;

        C d = new D();
        if (d.usesInterface() != 101)
            throw new RuntimeException();

        return 0;
    }

}
