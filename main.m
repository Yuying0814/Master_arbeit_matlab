
% The .env file must contain both the OpenAI API key and the Mistral AI API key.
% The keys can be obtained from the official OpenAI and Mistral AI websites:
%
% OpenAI: "https://help.openai.com/en/articles/4936850-where-do-i-find-my-openai-api-key"
% Mistral AI: "https://docs.mistral.ai/getting-started/quickstarts/developer/first-api-request"
% A free tier is available for the Mistral AI API key.
%
% The .env file should use the following format:
% OPENAI_API_KEY="$openai_api_key"
% MISTRALAI_API_KEY="$mistralai_api_key"

% File Path
env = "";
pdfFile = "D:\Study\MA\code\pdf\bst-bme280-ds002.pdf"; % "D:\Study\MA\pdf\bst-bme280-ds002.pdf"

% Load source code folder 
projectRoot = string(fileparts(mfilename("fullpath")));
srcDir = fullfile(projectRoot, "src");
addpath(srcDir);

% Load config
config = Config(env,pdfFile);

% 
textPreprocessor = preprocessing.Preprocessor(config);
textPreprocessor.run();





