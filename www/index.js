

var mod = undefined;
var setupBtn = undefined;
var setupTxt = undefined;
var txtArea = undefined;
var words_matching = [];
var letter_pool = "aaaaaaabbddddeeeffggghhiiiiiiiiikkkklllmmnnnnnoooppprrssssssttuuuvvwy";
const alphabet = "abcdefghijklmnopqrstuvwxyz";
var remaining_letters = undefined;
var text_entered = "";
var startTime = undefined;
var endTime = undefined;
var char_divs = {};


class WasmHandler {
  constructor() {
    this.memory = null;
  }

  logWasm(s, len) {
    const buf = new Uint8Array(this.memory.buffer, s, len);
    console.log(new TextDecoder("utf8").decode(buf));
  }

  showWords(s, len) {
    if (s == -1) {
      console.log("No Words Found");
      return;
    }
    endTime = new Date().getTime();
    console.log("Showing Words - Pointer: " + s + " Length: " + len);
    const buf = new Uint8Array(this.memory.buffer, s, len);
    const full_str = new TextDecoder("utf8").decode(buf);


    //console.log(JSON.stringify(full_str));
    var words = full_str.split("\n");
    if (startTime && endTime) {
      console.log("Time Elapsed: " + (endTime - startTime) + "ms");
      console.log("Time per Word: " + ((endTime - startTime) / words.length)+ "ms");
      startTime = undefined;
      endTime = undefined;
    }
    //words.sort();
    const word_div = document.getElementById("word-list");
    
   

    word_div.innerHTML = "<span>" + words.join(", </span><span>") + "</span>";

    checkValidString();
  }



  
}

async function instantiateWasmModule(wasm_handler) {
    const wasmEnv = {
      env: {
        logWasm: wasm_handler.logWasm.bind(wasm_handler),
        showWords: wasm_handler.showWords.bind(wasm_handler),
      },
    };

    const mod = await WebAssembly.instantiateStreaming(
        fetch("index.wasm"),
        wasmEnv,
    );

    wasm_handler.memory = mod.instance.exports.memory;

    return mod;
}



async function loadWordData(mod) {
    
    
      
  
    console.log("Loading Word Data");
    const word_data_response = await fetch("words2.txt");
    const data_reader = word_data_response.body.getReader( {
      mode: "byob",
    });
    let array_buf = new ArrayBuffer(16384);
    while (true) {
      const {value, done} = await data_reader.read(new Uint8Array(array_buf));
      if (done) break;
      array_buf = value.buffer;
      const chunk_buf = new Uint8Array(
        mod.instance.exports.memory.buffer,
        mod.instance.exports.global_chunk.value,
        16384,
      );
      //console.log("Pushing Word Data of length: ", value.length);
      chunk_buf.set(value);

      
      mod.instance.exports.pushWordData(value.length);
    }
    console.log("Finished Loading Word Data");
    mod.instance.exports.finishedPushing();
    let n_words = mod.instance.exports.getNWords();
    console.log("Added " + n_words + " words");


}

function validateString(letters) {
  
  letters = letters.toLowerCase();

  letters = letters.split("\n").join("").split(" ").join("");
  var validWord = "";

  Array.from(letters).forEach((character) => {
    if (alphabet.includes(character)) {
      validWord = validWord + character;
    }
  });

  return validWord;
}


function formatString(letters) {
  
  const textEncoder = new TextEncoder();

  const lettersArray = textEncoder.encode(letters);
  return lettersArray;
}

async function checkWords(mod, letters) {

  letter_pool = validateString(letters);
  remaining_letters = letter_pool;
  const lettersArray = formatString(letter_pool);
  //let array_buf = new ArrayBuffer(64);
  console.log("Checking Words: " + letter_pool);
  const chunk_buf = new Uint8Array(
    mod.instance.exports.memory.buffer,
    mod.instance.exports.global_chunk.value,
    2048,

  );

  chunk_buf.set(lettersArray)
  startTime = new Date().getTime();
  mod.instance.exports.getMatches(lettersArray.length);

  txtArea.addEventListener("input", updateMatches)
  txtArea.enabled = true;
  console.log("Enabled")
}

function checkValidString() {
  valid = true;

  string = txtArea.innerText.split("\n").join("").split(" ").join("");
  string = string.toLowerCase();
  remaining_letters = letter_pool;
  Array.from(string).forEach((character) => {
    character = character.trim();
    if (!remaining_letters.includes(character) && alphabet.includes(character)) {
      valid = false;
      console.log("Invalid Character: '" + character + "'");
    } else {
      remaining_letters = remaining_letters.replace(character, '');
    }
  });
  var char_amounts = {};
  Array.from(remaining_letters).forEach((character) => {
    if (character in char_amounts) {
      char_amounts[character] +=1;
    } else {
      char_amounts[character] = 1;
    }


  });

  Array.from(alphabet).forEach((character) => {
    if (character in char_amounts) {
      char_amounts[character] = Math.min(5, char_amounts[character]);
    }  else {
      char_amounts[character] = 0;
    }

    [0,1,2,3,4,5].forEach((num) => {
      char_divs[character].classList.remove("size"+num);
    })
    char_divs[character].classList.add("size"+char_amounts[character]);
});

  if (valid) {
    txtArea.classList.remove("invalid");
  } else {
    txtArea.classList.add("invalid");
  }
}



async function zigUpdateMatches(type) {


  const lettersArray = formatString(remaining_letters);
  //let array_buf = new ArrayBuffer(64);

  const chunk_buf = new Uint8Array(
    mod.instance.exports.memory.buffer,
    mod.instance.exports.global_chunk.value,
    2048,

  );

  chunk_buf.set(lettersArray)
  console.log("Updating Matches: " + remaining_letters + " Length: " + lettersArray.length);
  startTime = new Date().getTime();
  if (type == "add") {
    mod.instance.exports.addMatches(lettersArray.length);
  } else if (type=="remove") {
    mod.instance.exports.removeMatches(lettersArray.length);
  } else {
    mod.instance.exports.updateMatches(lettersArray.length);
  }

}



async function updateMatches(e) {

  console.log("inputType: " + e.inputType);
  if (e.inputType == "insertLineBreak" || e.inputType == "insertParagraph") {
    console.log("Preventing Default");
    e.preventDefault();
    return;
  }

  if (e.inputType == "insertReplacementText") {
    console.log("Paste | Target Ranges: " + e.getTargetRanges());

    await zigUpdateMatches("replace");
    return;  
  }

  if (e.inputType.startsWith("insert")) {

    await zigUpdateMatches("remove");
  }


  if (e.inputType.startsWith("delete")) {

    await zigUpdateMatches("add");
    return;
  }

}




async function checkLetters() {
  const letters = setupTxt.value;
  
  console.log("Checking Letters: " + letters);
  await checkWords(mod, letters);

}


async function init() {
  setupBtn = document.getElementById("setup-btn");
  setupTxt = document.getElementById("avail-chars")
  setupTxt.value = letter_pool;
  
  txtArea = document.getElementById("text-area");
  txtArea.enabled = false;
  
  const wasm_handler = new WasmHandler();
  mod = await instantiateWasmModule(wasm_handler);
  await loadWordData(mod);

  
  //mod.instance.exports.testPrint();
  //mod.instance.exports.printWordData(37);
  //mod.instance.exports.manyWords(false);
  //mod.instance.exports.manyWords(true);
  //await checkWords(mod, "test");
  var chart_div = document.getElementById("letter-chart");

  Array.from(alphabet).forEach((char) => {
      char_divs[char] = document.createElement("div");
      char_divs[char].classList.add("letter-box");
      char_divs[char].innerText = char
      chart_div.appendChild(char_divs[char]);
  });

  await checkLetters();
  
}



window.onload = init;

