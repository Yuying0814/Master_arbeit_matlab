classdef Mistral
    %MISTRALAI Summary of this class goes here
    %   Detailed explanation goes here
    properties (Access = private)
        ApiKey (1,1) string
    end

    
    methods
        function obj = Mistral(apiKey)
            arguments
                apiKey (1,1) string = ""
            end

            if isempty(apiKey) || strlength(apiKey) == 0
                error("Mistral:NoApiKey","Empty ApiKey Input");
            end

            obj.ApiKey = apiKey;
        end
        
        function ocrResult = runOcr(obj,pdfPath,ocrConfig)
            arguments
                obj (1,1) preprocessing.mistral.Mistral
                pdfPath {mustBeFile}
                ocrConfig.Model (1,1) string = "mistral-ocr-latest"
                ocrConfig.UrlExpiry (1,1) double = 24
                ocrConfig.TableFormat (1,1) string = "html"
                ocrConfig.IncludeImg (1,1) logical = true
            end

            model = ocrConfig.Model;
            urlExpiry = ocrConfig.UrlExpiry;
            tableFormat = ocrConfig.TableFormat;
            includeImg = ocrConfig.IncludeImg;

            % Upload pdf
            upResponse = obj.uploadFile(pdfPath);
            upResult = upResponse.Body.Data;

            if ~isfield(upResult, "id")
                error("ocr:InvalidUpResponse", "Invalid Up Response");
            end
        
            fileId = string(upResult.id);
            
            % Delete uploaded file after successful ocr or failure
            cleanupObj = onCleanup(@() obj.deleteFile(fileId));
            
            % Get signed url
            signedUrl = obj.getSignedUrl(fileId,urlExpiry);
                
            % Get ocr results
            ocrResult = obj.getOcrResult(signedUrl,model,tableFormat,includeImg);
        end
    end

    methods (Access = private)
        function upResponse = uploadFile(obj,pdfPath)
            import matlab.net.URI
            import matlab.net.http.RequestMessage
            import matlab.net.http.RequestMethod
            import matlab.net.http.HeaderField
            import matlab.net.http.io.FileProvider
            import matlab.net.http.io.MultipartFormProvider
            import matlab.net.http.StatusCode

            if ~isfile(pdfPath)
                error("Mistral:UploadFailed", ...
                    "File not found: %s", pdfPath);
            end
            
            destination = "https://api.mistral.ai/v1/files";
            provider = MultipartFormProvider( ...
                "purpose", "ocr", ...
                "file", FileProvider(pdfPath));
        
            headerAuth = HeaderField("Authorization", "Bearer " + obj.ApiKey);
            upReq = RequestMessage(RequestMethod.POST, headerAuth, provider);

            try
                upResponse = upReq.send(URI(destination));
            catch ME
                error("Mistral:UpRequestFailed", ...
                    "Failed to send upload request\n%s", ME.message);
            end
        
            if upResponse.StatusCode ~= StatusCode.OK
                error("Mistral:UpHttpError", "Upload http error:%s\n%s", ...
                    string(upResponse.StatusCode), ...
                    jsonencode(upResponse.Body.Data));
            end
        end

        function signedUrl = getSignedUrl(obj,fileId,urlExpiry)
            
            import matlab.net.URI
            import matlab.net.http.RequestMessage
            import matlab.net.http.RequestMethod
            import matlab.net.http.HeaderField
            import matlab.net.http.StatusCode
            
            destination = "https://api.mistral.ai/v1/files" + ...
                "/" + fileId + "/url?expiry=" + string(urlExpiry);
            headerAcpt = HeaderField("Accept", "application/json");
            headerAuth = HeaderField("Authorization", "Bearer " + obj.ApiKey);
            urlReq = RequestMessage(RequestMethod.GET, [headerAcpt headerAuth]);
    
            try
                urlResponse = urlReq.send(URI(destination));
            catch ME
                error("Mistral:UrlRequestFailed", ...
                    "Failed to send getSignedUrl request\n%s", ME.message);
            end
    
            if urlResponse.StatusCode ~= StatusCode.OK
                error("Mistral:UrlHttpError", "getUrl http error: %s\n%s", ...
                    string(urlResponse.StatusCode), ...
                    jsonencode(urlResponse.Body.Data));
            end
    
            urlResult = urlResponse.Body.Data;
    
            if ~isfield(urlResult, "url")
                error("Mistral:InvalidUrlResponse", "Invalid Url Response");
            end
    
            signedUrl = string(urlResult.url);
        end

        function ocrResult = getOcrResult(obj,signedUrl,model,tableFormat,includeImg)
            import matlab.net.URI
            import matlab.net.http.RequestMessage
            import matlab.net.http.RequestMethod
            import matlab.net.http.HeaderField
            import matlab.net.http.io.JSONProvider
            import matlab.net.http.StatusCode
            
            destination = "https://api.mistral.ai/v1/ocr";
            headerCont = HeaderField("Content-Type", "application/json");
            headerAuth = HeaderField("Authorization", "Bearer " + obj.ApiKey);
    
            reqBody = struct();
            reqBody.model = model;
            reqBody.document = struct( ...
                "type", "document_url", ...
                "document_url", signedUrl);
    
            reqBody.table_format = tableFormat;
            reqBody.include_image_base64 = includeImg;
    
            provider = JSONProvider(reqBody);
            ocrReq = RequestMessage(RequestMethod.POST, ...
                [headerCont headerAuth], provider);
    
            try
                ocrResponse = ocrReq.send(URI(destination));
            catch ME
                error("Mistral:OcrRequestFailed", ...
                    "Failed to send ocr request\n%s", ME.message);
            end
    
            if ocrResponse.StatusCode ~= StatusCode.OK
                error("Mistral:OcrHttpError", "ocr http error: %s\n%s", ...
                    string(ocrResponse.StatusCode), ...
                    jsonencode(ocrResponse.Body.Data));
            end
    
            ocrResult = ocrResponse.Body.Data;
        end

        function deleteFile(obj,fileId)
            import matlab.net.URI
            import matlab.net.http.RequestMessage
            import matlab.net.http.RequestMethod
            import matlab.net.http.HeaderField
            import matlab.net.http.StatusCode
            
            destination = "https://api.mistral.ai/v1/files" + "/" + fileId;
            headerAuth = HeaderField("Authorization", "Bearer " + obj.ApiKey);
            deleteReq = RequestMessage(RequestMethod.DELETE, headerAuth);
    
            try
                deleteResponse = deleteReq.send(URI(destination));
                if deleteResponse.StatusCode ~= StatusCode.OK
                    warning("Mistral:DeleteHttpError", ...
                        "delete http error: %s\n%s", ...
                        string(deleteResponse.StatusCode), ...
                        jsonencode(deleteResponse.Body.Data));
                end
            catch ME
                warning("Mistral:DeleteRequestFailed", ...
                    "Failed to send delete cleanup request\n%s", ME.message);
            end
        end
    end
end
