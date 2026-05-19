
env = "";
pdf = "D:\Study\MA\code\pdf\bst-bme280-ds002.pdf";

config = Config(env,pdf);
disp(config);

txtPrep = preprocessing.Preprocessor(config);

disp(txtPrep);
txtPrep.runOcr();
disp(txtPrep);
[contents messages responses]= txtPrep.classifyPages();
disp(txtPrep);
txtPrep.getRegPageIdx()
disp(txtPrep);


