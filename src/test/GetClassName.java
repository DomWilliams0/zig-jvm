public class GetClassName {
    public static int vmTest() {
        Object obj = new GetClassName();
        var name = obj.getClass().getName();
        return name.equals("GetClassName") ? 0 : 1;
    }

}
