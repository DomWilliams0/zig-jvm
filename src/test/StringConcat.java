public class StringConcat {

    public static int vmTest() {
        String s = "oof".concat(" wow");
        if (!s.equals("oof wow")) throw new RuntimeException(s);
        return 0;
            
    }
}