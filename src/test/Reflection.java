//! system 
import java.lang.reflect.InvocationTargetException;

public class Reflection {
    int i = 5;
    String s = "nice";

    Reflection() {}
    public Reflection(int i) {this.i = i;}

    
    public static int vmTest() throws NoSuchMethodException, SecurityException, InstantiationException, IllegalAccessException, IllegalArgumentException, InvocationTargetException {

        var cons = Reflection.class.getDeclaredConstructor();
        Reflection r = cons.newInstance();
        if (r.i != 5) throw new RuntimeException();
        if (!r.s.equals("nice")) throw new RuntimeException();

        var cons2 = Reflection.class.getConstructor(int.class);
        Reflection r2 = cons2.newInstance(55);
        if (r2.i != 55) throw new RuntimeException();
        return 0;


    }
}
