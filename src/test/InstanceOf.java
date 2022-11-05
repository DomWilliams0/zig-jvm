public class InstanceOf {
    static class A { }

    static class B extends A {
    }

    public static int vmTest() {
        var a = new A();
        if (a instanceof B)
            throw new RuntimeException();
        return 0;
    }

}
