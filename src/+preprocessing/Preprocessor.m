classdef Preprocessor < handle
    properties
        PdfPath string
        OcrResult struct = struct([])
        Pages struct = struct([])
        TocPageIdx double = [];
        TocEntries struct = struct([])
        
        RegPageIdxFromToc double = []
        RegPageIdxFromRetrieval double = []
        RegPageIdxFromLLM double = []
        RegPageIdxCandidate double = []
        RegPageIdx double = []
        
        RegSumIdxFromToc double = []
        RegSumIdxFromRetrieval double = []
        RegSumIdxFromLLM double = []
        RegSumIdxCandidate double = []
        RegSumPageIdx double = []
        
        RegSummary struct = struct([])
        RegMap struct = struct([])

        BatchClient  openai.OpenaiBatch = openai.OpenaiBatch.empty
        MistralClient preprocessing.mistral.Mistral = preprocessing.mistral.Mistral.empty
        
    end

    properties(Access=private)
        Config Config = Config.empty
    end
    
    methods
        function obj = Preprocessor(config)
            arguments
                config Config
            end

            pdfPath = string(config.Paths.PdfPath);
            if ~isfile(pdfPath)
                error("Preprocessor:MissingFile","No such file: %s",pdfPath);
            end
            
            obj.Config = config;
            obj.PdfPath = pdfPath;
            obj.BatchClient = openai.OpenaiBatch(config.getKey("openai"));
            obj.MistralClient = preprocessing.mistral.Mistral(config.getKey("mistral"));

        end

        function runOcr(obj,mistral)
            arguments
                obj (1,1) preprocessing.Preprocessor
                mistral (1,1) preprocessing.mistral.Mistral = obj.MistralClient
            end
            ocrConfig = obj.Config.Mistral.Task.Ocr; 
            
            ocrResult = mistral.runOcr( ...
                obj.PdfPath, ...
                Model=ocrConfig.Model, ...
                UrlExpiry=ocrConfig.UrlExpiry, ...
                IncludeImg=ocrConfig.IncludeImg, ...
                TableFormat=ocrConfig.TableFormat);
            
            pages = struct( ...
                'index',{ocrResult.pages.index}, ...
                'markdown', {ocrResult.pages.markdown}, ...
                'tables',  {ocrResult.pages.tables});
            pages = preprocessing.utils.removeHeaderFooter(pages);
            
            obj.OcrResult = ocrResult;
            obj.Pages = pages;
        end

        function saveOcrResult(obj,outputPath)
            jsonText = jsonencode(obj.OcrResult);
            fid = fopen(outputPath, "w");
        
            if fid == -1
                error("ocr:OutputFileOpenFailed", ...
                    "Failed to open file: %s", outputPath);
            end
            
            try
                fprintf(fid, "%s", jsonText);
                fclose(fid);
            catch ME
                if fid ~= -1
                    fclose(fid);
                end
                error("ocr:OutputFileWriteFailed", ...
                    "Failed to write to file: %s\n%s", outputPath, ME.message);
            end
        end

        function getRegPageIdx(obj)
            %% Get register-map-page and register-summary page number from toc
            pages = preprocessing.toc.findTocPages(obj.Pages);
            tocIdx = find(arrayfun(@(onePage) onePage.result_toc.is_toc, pages));
            tocEntries = preprocessing.toc.extractTocEntry(pages(tocIdx));
            [regPageIdx,regSumIdx] = preprocessing.toc.resolveTocEntries(tocEntries);
            
            obj.RegPageIdxFromToc = regPageIdx;
            obj.RegSumIdxFromToc = regSumIdx;
            obj.TocEntries = tocEntries;
            obj.TocPageIdx = tocIdx;
            
            %% Get register-map-page and register-summary page number through whole-text-retrieval
            pages = preprocessing.retrieval.findRelevantPageRange(pages,"register");
            regPageIdx = find(arrayfun(@(onePage) onePage.result_retrieval.is_reg_map_relevant, pages));
            regSumIdx = find(arrayfun(@(onePage) onePage.result_retrieval.is_reg_sum_relevant, pages));

            obj.RegPageIdxFromRetrieval = regPageIdx;
            obj.RegSumIdxFromRetrieval = regSumIdx;

            %% Get register-map-page and register-summary page number from LLM
            regPageIdx = find(arrayfun(@(onePage) onePage.classification.is_register_map_relevant, pages));
            regSumIdx = find(arrayfun(@(onePage) onePage.classification.is_register_summary_relevant, pages));

            obj.RegPageIdxFromLLM = regPageIdx;
            obj.RegSumIdxFromLLM = regSumIdx;


            obj.RegPageIdxCandidate = unique([obj.RegPageIdxFromToc obj.RegPageIdxFromRetrieval obj.RegPageIdxFromLLM]);
            obj.RegSumIdxCandidate = unique([obj.RegSumIdxFromToc obj.RegSumIdxFromRetrieval obj.RegSumIdxFromLLM]);
            obj.Pages = pages;
        end

        function [contents,messages,batchLines] = classifyPages(obj,batchClient)
            arguments
                obj (1,1) preprocessing.Preprocessor 
                batchClient (1,1) openai.OpenaiBatch = obj.BatchClient
            end

            pages = obj.Pages;
            taskConfig = obj.Config.Openai.Task.classifyPages;
            inputPath = fullfile(obj.Config.Paths.InputDir,"classification_req.jsonl");

            [pages,contents,messages,batchLines] = preprocessing.classification.runClassification( ...
                pages, ...
                batchClient, ...
                taskConfig, ...
                inputPath);

            obj.Pages = pages;
        end

        % function [contents,message,batchLines] = verifyRegisterPages(obj,batchClient)
        %     arguments
        %         obj (1,1) preprocessing.Preprocessor 
        %         batchClient (1,1) openai.OpenaiBatch = obj.BatchClient
        %     end
        % 
        %     pages = obj.Pages;
        % 
        %     regPages = pages(obj.RegPageIdxCandidate);
        %     regSumPages = pages(obj.RegSumIdxCandidate);
        % 
        %     [regPageIdx,contents,message,batchLines] = preprocessing.classification.runValidation( ...
        %         regPages, ...
        %         regSumPages, ...
        %         batchClient, ...
        %         taskConfig, ...
        %         inputPath);
        % 
        %     obj.RegPageIdx = regPageIdx;
        %     obj.RegSumPageIdx = regSumPageIdx;
        % end
        % 
        % function extractRegisterIdx(obj)
        % 
        % end
        % 
        % function extractRegisterMap(obj)
        % 
        % end
   

    end
    
    methods (Access = private)

    end
end
        