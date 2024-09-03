words_list = []

ALPHABET = "abcdefghijklmnopqrstuvwxyz"

def write_words(words):
    with open("www/words2.txt", "w") as file:
        for word in words:
            valid = True
            for c in word:
                if c in ALPHABET:
                    continue
                valid = False
                break
            if valid:
                file.write(word + "\n")



with open("www/words.txt", "r") as file:
    while True:
        line = file.readline().split()

        if not line:
            break
        if int(line[0]) > 100:
            if line[1][0].isupper():
                continue
            words_list.append(line[1].lower())
        
unique_list = list(dict.fromkeys(words_list))


write_words(unique_list)