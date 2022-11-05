public class LookupSwitch {
    public static int vmTest() {
        // take the default branch
        int i = 50;

        switch (i) {
            case 0:
            case 5:
            case 12:
            case 20:
            case 49:
                throw new RuntimeException();
            default:
                i -= 50;
                break;
        }

        // take a case branch
        String val = "nice";
        switch (val) {
            case "ooh":
            case "wow":
                throw new RuntimeException();
            case "nice":
                break; // nice
            default:
                throw new RuntimeException();
        }

        return i;
    }

}
