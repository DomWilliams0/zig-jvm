import java.util.HashMap;
import java.util.Map;

public class Interface {
    public static int vmTest() {
        // invokeinterface
        Map<String, String> map = new HashMap<String, String>();
        map.clear();
        map.put("five", "fifty");

        // checkcast(java/util/HashMap$Node, java/util/Map$Entry)
        for (var e : map.entrySet()) {

        }
        return 0;
    }
}
