classdef Config < handle
    %Summary of this class goes here
    %   Detailed explanation goes here

    properties (SetAccess = private)
        Paths (1,1) struct = struct( ...
            "RootPath", "", ...
            "PdfPath","", ...
            "InputDir", "", ...
            "OutputDir", "", ...
            "LLMDir", "", ...
            "PromptsDir", "", ...
            "SrcDir", "", ...
            "EnvPath", "", ...
            "TestsDir","" ...
            )
        
        Openai (1,1) struct = struct( ...
            "TimeOut",[], ...
            "Task",struct() ...
            )
        
        Mistral (1,1) struct = struct( ...
            "Task",struct() ...
            )
    end

    methods
        function obj = Config(env,pdf)
            % Construct an instance of this class
            %   Detailed explanation goes here
            arguments
                env {mustBeTextScalar} = ""
                pdf {mustBeTextScalar} = ""
            end

            configFile = string(mfilename("fullpath"));
            srcDir = string(fileparts(configFile));
            rootPath = string(fileparts(srcDir));
            
            env = string(env);      
            pdf = string(pdf);
            
            if strlength(pdf) == 0
                error("Config:NoInput", "No pdf input");
            end

            % Default .env file path at project path
            if strlength(env) == 0
                env = fullfile(rootPath, ".env");
            end

            if ~isfile(env)
                error("Config:MissingFile", "No such file: %s", env);
            end


            if ~isfile(pdf)
                error("Config:MissingFile", "No such file: %s", pdf);
            end

            absEnvPath = dir(env);
            absPdfPath = dir(pdf);

            envPath = string(fullfile(absEnvPath.folder,absEnvPath.name));
            pdfPath = string(fullfile(absPdfPath.folder,absPdfPath.name));
            
            obj.Paths = buildPath(rootPath);
            obj.Paths.EnvPath = envPath;
            obj.Paths.PdfPath = pdfPath;

            obj.loadEnv();
            obj.loadPath();
            obj.buildOpenaiTaskConfig();
            obj.buildMistralConfig();
        end
        
        function apiKey = getKey(~,option)
            %METHOD1 Summary of this method goes here
            %   Detailed explanation goes here
            arguments
                ~
                option {mustBeTextScalar}
            end
            
            option = lower(string(option));

            switch option
                case "openai"
                    apiKey = getenv("OPENAI_API_KEY");
                case "mistral"
                    apiKey = getenv("MISTRALAI_API_KEY");
                otherwise
                    options = ["openAI" "mistralAI"];
                    validOptions = join(options,"|");
                    error("Config:InvalidKeyOption","Input must be one of: %s",validOptions);
            end

            apiKey = strtrim(string(apiKey));

            if strlength(string(apiKey)) == 0
                error("Config:MissingApiKey","No API key found: %s",option);
            end
        end
    end

    methods (Access = private)
        function buildOpenaiTaskConfig(obj)

            obj.Openai.TimeOut = 3000;

            % Define task Configurations
            % obj.Openai.Task.xxx.ModelName = "";
            % obj.Openai.Task.xxx.PromptPath = "";
            % obj.Openai.Task.xxx.ResponseFormat = "";
            % obj.Openai.Task.xxx.Tools = "";
            
            obj.Openai.Task.classifyPages.ModelName = "gpt-5-mini";
            obj.Openai.Task.classifyPages.PromptPath = fullfile(obj.Paths.PromptsDir,"prompt_classifyPages.txt");
            obj.Openai.Task.classifyPages.ResponseFormat = preprocessing.page.getClassificationFormat();
            obj.Openai.Task.classifyPages.MaxCompletionTokens = 2000;
            
            obj.Openai.Task.verifyRegSumPages.ModelName = "gpt-5-mini";
            obj.Openai.Task.verifyRegSumPages.PromptPath = fullfile(obj.Paths.PromptsDir,"prompt_verifyRegSumPages.txt");
            obj.Openai.Task.verifyRegSumPages.ResponseFormat = "text";
            obj.Openai.Task.verifyRegSumPages.MaxCompletionTokens = 1000;

            obj.Openai.Task.verifyRegPages.ModelName = "gpt-5-mini";
            obj.Openai.Task.verifyRegPages.PromptPath = fullfile(obj.Paths.PromptsDir,"prompt_verifyRegPages.txt");
            obj.Openai.Task.verifyRegPages.ResponseFormat = "text";
            obj.Openai.Task.verifyRegPages.MaxCompletionTokens = 1000;

            obj.Openai.Task.addPageDescription.ModelName = "gpt-5-mini";
            obj.Openai.Task.addPageDescription.PromptPath = fullfile(obj.Paths.PromptsDir,"prompt_addPageDescription.txt");
            obj.Openai.Task.addPageDescription.ResponseFormat = preprocessing.page.getDescriptionFormat();
            obj.Openai.Task.addPageDescription.MaxCompletionTokens = 2000;

            obj.Openai.Task.extractRegIndex.ModelName = "gpt-5-mini";
            obj.Openai.Task.extractRegIndex.PromptPath = fullfile(obj.Paths.PromptsDir,"prompt_extractRegIndex.txt");
            obj.Openai.Task.extractRegIndex.ResponseFormat = preprocessing.register.getRegIndexDefaultFormat();

            obj.Openai.Task.extractRegMap.ModelName = "gpt-5-mini";
            obj.Openai.Task.extractRegMap.PromptPath = fullfile(obj.Paths.PromptsDir,"prompt_extractRegMap.txt");
            obj.Openai.Task.extractRegMap.ResponseFormat = preprocessing.register.getRegMapDefaultFormat();
        end

        function buildMistralConfig(obj)
            % Define task Configurations
            % obj.Mistral.Task.Ocr.Model = "";
            % obj.Mistral.Task.Ocr.UrlExpiry = ;
            % obj.Mistral.Task.Ocr.TableFormat = "";
            % obj.Mistral.Task.Ocr.IncludeImg = ;

            obj.Mistral.Task.Ocr.Model = "mistral-ocr-latest";
            obj.Mistral.Task.Ocr.UrlExpiry = 24;
            obj.Mistral.Task.Ocr.TableFormat = "html";
            obj.Mistral.Task.Ocr.IncludeImg = true;
        end

        function loadEnv(obj)
            try
                loadenv(obj.Paths.EnvPath);
            catch ME
                error("Config:LoadEnvfailed","Failed to load environment file: %s\n%s",obj.Paths.EnvPath,ME.message);
            end
        end

        function loadPath(obj)
            if ~isfolder(obj.Paths.LLMDir)
                error("Config:MissingLLMPackage","Missing package of llms-with-matlab-main.\n" + ...
                    "This script requires support from package llms-with-matlab-main, " + ...
                    "which can be downloaded from: \n" + ...
                    "https://github.com/matlab-deep-learning/llms-with-matlab");
            end
            addpath(obj.Paths.LLMDir);
        end
    end
end

function paths = buildPath(rootPath)
    paths.PdfPath = "";
    paths.EnvPath = "";
    paths.RootPath = rootPath;
    paths.InputDir = fullfile(rootPath, "data", "input");
    paths.OutputDir = fullfile(rootPath, "data", "output");
    paths.LLMDir = fullfile(rootPath, "llms-with-matlab-main");
    paths.PromptsDir = fullfile(rootPath, "prompts");
    paths.SrcDir = fullfile(rootPath, "src");
    paths.TestsDir = fullfile(rootPath, "tests");
end