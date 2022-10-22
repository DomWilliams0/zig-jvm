import bs4

with open("instructions.html") as f:
    soup = bs4.BeautifulSoup(f.read())
    soup.prettify()

insns = []
first=True
for elem in soup.findAll("div", {"class":"literallayout"}):
    if first:
        first = False
        continue
    txt = elem.text.strip().split()
    number = elem.next_sibling.find_next("p").text
    try:
        print(number)
        number = number.split("=")[1].split("(")[0].strip()
        insns.append(dict(name=txt[0], id=int(number), size=len(txt)-1))
    except:
        print("SKIP", txt)
        continue

    i = insns[-1]
    if i["name"].endswith("_<n>"):
        i["name"] = i["name"].replace("<n>", "0")

        for j in range(1,4):
            import copy
            k = copy.deepcopy(i)
            k["id"] += j
            k["name"] = k["name"][:-1] + str(j)
            insns.append(k)


    # print(txt)
    print("----")


insns.sort(key=lambda i: (i["name"][1:], i["id"], i["name"][0]))

for i in insns:
    print(f'.{{.name="{i["name"]}", .id={i["id"]}, .sz={i["size"]} }},')
